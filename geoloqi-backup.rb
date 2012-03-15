#!/usr/bin/ruby

require 'rubygems'
require 'active_record'
require 'active_support'
require 'yaml'
require 'geoloqi'

@config = YAML.load_file("#{File.dirname((File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__))}/config.yml")

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
		e.raw_data = point.to_json
		e.save
	end

    def self.info
		raise "not yet implemented"
        puts "Tweets in DB: #{Tweet.count}"
        puts "Neuester Tweet: #{Tweet.last.date} (vor #{(Time.now - Tweet.last.date) / 60} Minuten)"
    end

end

#if opt["nagios"]
#	raise "not yet implemented"
#    diff = Time.now - Tweet.last.date # in Sekunden
#    puts "Neuester Tweet ist #{(diff / 60).round} Minuten alt."
#    exit 2 if diff > (24*60*60) # 24 Stunden - CRITICAL
#    exit 1 if diff > (12*60*60) # 12 Stunden - WARNING
#    exit 0 # Alles OK
#end

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

def generate_graphic
	require 'RMagick'
	canvas = Magick::Image.new(1000, 1000)
	gc = Magick::Draw.new
	gc.stroke('black')

	min_lat = Entry.find(:first, :order=>'latitude ASC', :limit=>1).latitude
	min_lon = Entry.find(:first, :order=>'longitude ASC', :limit=>1).longitude
	max_lat = Entry.find(:first, :order=>'latitude DESC', :limit=>1).latitude
	max_lon = Entry.find(:first, :order=>'longitude DESC', :limit=>1).longitude

	lat_diff = max_lat - min_lat
	lon_diff = max_lon - min_lon

	max_diff = [lat_diff, lon_diff].max

	factor = 1000 / max_diff

	Entry.all.each do |point|
		y = 1000 - (point.latitude - min_lat)*factor
		x = (point.longitude - min_lon)*factor
		gc.point(x, y)
	end

	gc.draw(canvas)
	canvas.write(File.join(File.dirname(__FILE__), "image.png"))
end

update
generate_graphic
