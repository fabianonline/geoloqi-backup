#!/usr/bin/ruby

require 'rubygems'
require 'active_record'
require 'yaml'
require 'geoloqi'
require 'getopt/long'
require 'RMagick'

$config = YAML.load_file("#{File.dirname((File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__))}/config.yml")

GEOLOQI_VERSION="0.2"
DEBUG_GENERATE_IMAGE_TIMES=false

ActiveRecord::Base.establish_connection(
    :adapter => 'mysql',
    :host =>     $config['mysql']['host'],
    :username => $config['mysql']['username'],
    :password => $config['mysql']['password'],
    :database => $config['mysql']['database'],
    :encoding => $config['mysql']['encoding'])

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
	
	def self.add_multiple_points(array)
		puts "    Creating query..." if $verbose
		fields = "(date, latitude, longitude, speed, altitude, heading, accuracy, uuid, battery)"
		data = []
		array.each do |point|
			temp_data = ["FROM_UNIXTIME(#{point[:date_ts]})",
				point[:location][:position][:latitude],
				point[:location][:position][:longitude],
				point[:location][:position][:speed],
				point[:location][:position][:altitude],
				point[:location][:position][:heading],
				point[:location][:position][:horizontal_accuracy],
				"'#{point[:uuid]}'",
				(point[:raw][:battery] rescue "NULL")]
			data.push "(#{temp_data.join(', ')})"
		end
		sql = "INSERT INTO #{Entry.table_name} #{fields} VALUES \n  #{data.join(", \n  ")}"
		puts sql if $verbose
		print "    Executing Query... " if $verbose
		Entry.connection.execute(sql) unless $dry_run
	end
end


def latlontomerc(x, y)
	x = x * 6378137.0 * Math::PI / 180.0
	y = Math::asinh(Math::tan(y / 180.0 * Math::PI)) * 6378137.0
	return [x, y]
end

def merctolatlon(x, y)
	lon = (x / 6378137.0) / Math::PI * 180
	lat = Math::atan(Math::sinh(y / 6378137.0)) / Math::PI * 180
	return [lat, lon]
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
		if $verbose
			puts
		else
			print Time.now.strftime "| %d.%m.%y %H:%M | "
		end
		start = Entry.find(:first, :order=>'date DESC').date.to_i rescue "0"
		if $verbose
			puts "Getting up to #{$config['geoloqi']['results_count']} entries starting at #{start}... "
		else
			print "%6d | " % $config['geoloqi']['results_count']
			print "%10d | " % start
		end
		response = Geoloqi.get($config['geoloqi']['access_key'], 'location/history', 
			:count => $config['geoloqi']['results_count'],
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
		Entry.add_multiple_points(response[:points])
		puts ""
	end while true
end

def generate_image(bbox, o={})
	values = [] if DEBUG_GENERATE_IMAGE_TIMES
	start_total = Time.now.to_f if DEBUG_GENERATE_IMAGE_TIMES
	opts = {
		:background=>'transparent',
		:color=>'black',
		:use_cached_version=>true,
		:save_in_cache=>true,
		:width=>256,
		:height=>256,
		:additional_conditions=>[],
		:color_by=>nil
	}.merge(o)

	box = bbox.split(",")
	big_dots = (box[2].to_f - box[0].to_f)<$config["map"]["big_dot_level"]
	bbox1 = merctolatlon(box[0].to_f, box[1].to_f)
	bbox2 = merctolatlon(box[2].to_f, box[3].to_f)
	zoomlevel = (17-((Math.log((box[2].to_f-box[0].to_f).abs*3.281/500) / Math.log(2)).round))
	big_dots = zoomlevel>=$config["map"]["big_dot_level"]
	filename = File.join(File.dirname(__FILE__), "public", "image_cache", ("%02d" % zoomlevel), "#{bbox}.png")
	FileUtils.mkdir_p(File.dirname(filename))
	canvas = Magick::Image.new(opts[:width], opts[:height]) { self.background_color = opts[:background] }
	gc = Magick::Draw.new
	gc.stroke(opts[:color])
	gc.fill(opts[:color])

	min_lat = bbox1[0]
	min_lon = bbox1[1]
	max_lat = bbox2[0]
	max_lon = bbox2[1]
	
	x_factor = opts[:width]/ (bbox2[1]-bbox1[1])
	y_factor = opts[:height] / (bbox2[0]-bbox1[0])
	
	conditions = ["accuracy<=#{$config["map"]["max_accuracy"]}", "latitude>=#{min_lat}", "latitude<=#{max_lat}", "longitude>=#{min_lon}", "longitude<=#{max_lon}"]
	conditions = conditions + opts[:additional_conditions]

	if opts[:use_cached_version]
		if File.exists?(filename)
			canvas = Magick::ImageList.new(filename).first
			conditions << "date>=FROM_UNIXTIME(#{File.mtime(filename).to_i})"
		else
			# Bild existiert nicht im Cache - könnte also auch leer sein...
			filename = File.join(File.dirname(filename), "empty.png") if Entry.count(:conditions=>conditions.join(" && "))==0
		end
	end

	start = Time.now.to_f if DEBUG_GENERATE_IMAGE_TIMES
	first = true if DEBUG_GENERATE_IMAGE_TIMES
	Entry.find_each(:conditions=>[conditions.join(" && ")], :select=>"id, latitude, longitude, accuracy") do |point|
		if DEBUG_GENERATE_IMAGE_TIMES && first
			values << (Time.now.to_f - start)
			first = false
			start = Time.now.to_f
		end
		if opts[:color_by]==:accuracy
			color = "red"
			color = "yellow" if point.accuracy<=30
			color = "green" if point.accuracy<=10
			gc.fill(color)
			gc.stroke(color)
		end
		y = (opts[:height] - (point.latitude - min_lat)*y_factor).round
		x = ((point.longitude - min_lon)*x_factor).round
		if big_dots
			gc.rectangle(x-1, y-1, x+1, y+1)
		else
			gc.point(x,y)
		end
		print "."
	end
	values << (Time.now.to_f - start) if DEBUG_GENERATE_IMAGE_TIMES && !first

	gc.draw(canvas)
	image = canvas.to_blob {self.format="png"}
	
	if opts[:save_in_cache]
		File.open(filename, "w") {|f| f.write(image) } rescue nil
	end
	puts
	
	values << (Time.now.to_f - start_total) if DEBUG_GENERATE_IMAGE_TIMES
	File.open(File.join(File.dirname(__FILE__), "log.log"), "a") {|f| f.write(values.join(';') + "\n")} if DEBUG_GENERATE_IMAGE_TIMES
	return image
end

opt = Getopt::Long.getopts(
	['--update', '-u'],
	['--nagios', '-n'],
	['--info', '-i'],
	['--help', '-h'],
	['--dry-run'],
	['--verbose']
) rescue {}

if opt["help"]
	puts <<EOF
geoloqi-backup Version #{GEOLOQI_VERSION}

  --update,  -u   Lädt neue Datensätze von Geoloqi herunter und speichert sie
                  in der MySQL-Datenbank.
  --info,    -i   Zeigt Infos über die in der Datenbank gespeicherten Einträge.
  --nagios,  -n   Gibt Daten zum Tracking via Nagios aus.
  --dry-run       Nimmt keine Änderungen vor.
  --verbose       Gibt mehr (zu viele?) Infos aus.
  --help,    -h   Diese Hilfe.
EOF
	exit
end

$verbose = opt.has_key? "verbose"
$dry_run = opt.has_key? "dry-run"

update if opt["update"]
info if opt["info"]
nagios if opt["nagios"]








##########################################
# Sinatra Stuff
##########################################

if defined?(::Sinatra) && defined?(::Sinatra::Base)
	before do
		ActiveRecord::Base.connection.verify!
	end

	get '/' do
		@min_lat = Entry.find(:first, :order=>'latitude ASC', :conditions=>["accuracy<#{$config["map"]["max_accuracy"]}"], :limit=>1).latitude
		@min_lon = Entry.find(:first, :order=>'longitude ASC', :conditions=>["accuracy<#{$config["map"]["max_accuracy"]}"], :limit=>1).longitude
		@max_lat = Entry.find(:first, :order=>'latitude DESC', :conditions=>["accuracy<#{$config["map"]["max_accuracy"]}"], :limit=>1).latitude
		@max_lon = Entry.find(:first, :order=>'longitude DESC', :conditions=>["accuracy<#{$config["map"]["max_accuracy"]}"], :limit=>1).longitude
		
		lat_diff = @max_lat - @min_lat
		lon_diff = @max_lon - @min_lon
		max_diff = [lat_diff, lon_diff].max
		
		@max_lon = @min_lon + max_diff
		@max_lat = @min_lat + max_diff
		
		erb :index
	end
	
	get '/test' do
		return $config.inspect
	end
	
	get '/wms' do
		headers "Content-Type" => "image/png"
		p = {:width=>params[:WIDTH].to_i, :height=>params[:HEIGHT].to_i}
		if params[:TYPE] == "all"
			p.merge!({:color=>'#999'})
		else
			p.merge!({:use_cached_version=>false, :save_in_cache=>false, :additional_conditions=>["date>=FROM_UNIXTIME(#{Time.now.to_i - 24*60*60})"]})
		end
		return generate_image(params[:BBOX], p)
	end
end

