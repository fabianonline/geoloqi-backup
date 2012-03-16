#!/usr/bin/ruby

require 'rubygems'
require 'active_record'
require 'yaml'
require 'geoloqi'
require 'getopt/long'
require 'RMagick'

@config = YAML.load_file("#{File.dirname((File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__))}/config.yml")

GEOLOQI_VERSION="0.2"

ActiveRecord::Base.establish_connection(
    :adapter => 'mysql',
    :host =>     @config['mysql']['host'],
    :username => @config['mysql']['username'],
    :password => @config['mysql']['password'],
    :database => @config['mysql']['database'],
    :encoding => @config['mysql']['encoding'])

class Entry < ActiveRecord::Base
	validates_uniqueness_of :date

    def self.add(point)
		return unless point
		e = Entry.new
		e.date = Time.at point[:date_ts]
		e.latitude = point[:location][:position][:latitude]
		e.longitude = point[:location][:position][:longitude]
		e.speed = point[:location][:position][:speed]
		e.altitude = point[:location][:position][:altitude]
		e.heading = point[:location][:position][:heading]
		e.accuracy = point[:location][:position][:horizontal_accuracy]
		e.uuid = point[:uuid]
		e.battery = point[:raw][:battery] rescue nil
		e.save
	end
end

def nagios
	diff = Time.now - Entry.last.date # in Sekunden
	puts "Neuester Entry ist #{(diff / 60).round} Minuten alt."
	exit 2 if diff > (3*24*60*60) # 3 Tage - CRITICAL
	exit 1 if diff > (24*60*60) # 1 Tag - WARNING
	exit 0 # Alles OK
end

def info
	puts "Entries in DB: #{Entry.count}"
	puts "Newest Entry: #{Entry.last.date} (vor #{(Time.now - Entry.last.date) / 60} Minuten)"
end

def update
	begin
		start = Entry.find(:first, :order=>'date DESC').date.to_i rescue "0"
		puts "Getting up to #{@config['geoloqi']['results_count']} entries starting at #{start}... "
		response = Geoloqi.get(@config['geoloqi']['access_key'], 'location/history', 
			:count => @config['geoloqi']['results_count'],
			:accuracy => 500,
			:ignore_gaps => 1,
			:after => start,
			:sort => :asc
		)
		if response.empty? || response[:points].empty?
			puts "Empty result. Exiting."
			return
		end

		puts "Got #{response[:points].count} results. Adding to database..."
		response[:points].each {|point| Entry.add(point)}
		puts ""
	end while true
end

opt = Getopt::Long.getopts(
	['--update', '-u'],
	['--nagios', '-n'],
	['--info', '-i'],
	['--help', '-h']
) rescue {}

if opt["help"]
	puts <<EOF
geoloqi-backup Version #{GEOLOQI_VERSION}

  --update,  -u   Lädt neue Datensätze von Geoloqi herunter und speichert sie
                  in der MySQL-Datenbank.
  --info,    -i   Zeigt Infos über die in der Datenbank gespeicherten Einträge.
  --nagios,  -n   Gibt Daten zum Tracking via Nagios aus.
  --help,    -h   Diese Hilfe.
EOF
	exit
end

update if opt["update"]
info if opt["info"]
nagios if opt["nagios"]








##########################################
# Sinatra Stuff
##########################################

if defined?(::Sinatra) && defined?(::Sinatra::Base)
	get '/' do
		@min_lat = Entry.find(:first, :order=>'latitude ASC', :conditions=>["accuracy<100"], :limit=>1).latitude
		@min_lon = Entry.find(:first, :order=>'longitude ASC', :conditions=>["accuracy<100"], :limit=>1).longitude
		@max_lat = Entry.find(:first, :order=>'latitude DESC', :conditions=>["accuracy<100"], :limit=>1).latitude
		@max_lon = Entry.find(:first, :order=>'longitude DESC', :conditions=>["accuracy<100"], :limit=>1).longitude
		
		lat_diff = @max_lat - @min_lat
		lon_diff = @max_lon - @min_lon
		max_diff = [lat_diff, lon_diff].max
		
		@max_lon = @min_lon + max_diff
		@max_lat = @min_lat + max_diff
		
		erb :index
	end
	
	get '/wms' do
		headers "Content-Type" => "image/png"
		box = params[:BBOX].split(",")
		big_dots = (box[2].to_f - box[0].to_f)<3000
		bbox1 = merctolatlon(box[0].to_f, box[1].to_f)
		bbox2 = merctolatlon(box[2].to_f, box[3].to_f)
		canvas = Magick::Image.new(params[:WIDTH].to_i, params[:HEIGHT].to_i) { self.background_color = "transparent" }
		gc = Magick::Draw.new
		gc.stroke('black')
		gc.fill('black')

		min_lat = bbox1[0]
		min_lon = bbox1[1]
		max_lat = bbox2[0]
		max_lon = bbox2[1]
		
		x_factor = params[:WIDTH].to_i / (bbox2[1]-bbox1[1])
		y_factor = params[:HEIGHT].to_i / (bbox2[0]-bbox1[0])

		Entry.find(:all, :conditions=>["accuracy<100 && latitude>#{min_lat} && latitude<#{max_lat} && longitude>#{min_lon} && longitude<#{max_lon}"]).each do |point|
			y = params[:HEIGHT].to_i - (point.latitude - min_lat)*y_factor
			x = (point.longitude - min_lon)*x_factor
			if big_dots
				gc.rectangle(x-1, y-1, x+1, y+1)
			else
				gc.point(x,y)
			end
		end

		gc.draw(canvas)
		canvas.to_blob {self.format="png"}
	end
end



def merctolatlon(x, y)
	lon = (x / 6378137.0) / Math::PI * 180
	lat = Math::atan(Math::sinh(y / 6378137.0)) / Math::PI * 180
	return [lat, lon]
end