#!/usr/bin/ruby

require 'rubygems'
require 'active_record'
require 'yaml'
require 'geoloqi'
require 'getopt/long'

@config = YAML.load_file("#{File.dirname((File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__))}/config.yml")

GEOLOQI_VERSION="0.1"

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

def generate_graphic
	require 'RMagick'
	canvas = Magick::Image.new(@config['image_size'], @config['image_size']) { self.background_color = "transparent" }
	gc = Magick::Draw.new
	gc.stroke('black')

	min_lat = Entry.find(:first, :order=>'latitude ASC', :conditions=>["accuracy<100"], :limit=>1).latitude
	min_lon = Entry.find(:first, :order=>'longitude ASC', :conditions=>["accuracy<100"], :limit=>1).longitude
	max_lat = Entry.find(:first, :order=>'latitude DESC', :conditions=>["accuracy<100"], :limit=>1).latitude
	max_lon = Entry.find(:first, :order=>'longitude DESC', :conditions=>["accuracy<100"], :limit=>1).longitude

	lat_diff = max_lat - min_lat
	lon_diff = max_lon - min_lon
	max_diff = [lat_diff, lon_diff].max

	factor = @config['image_size'] / max_diff

	Entry.find(:all, :conditions=>["accuracy<100"]).each do |point|
		y = @config['image_size'] - (point.latitude - min_lat)*factor
		x = (point.longitude - min_lon)*factor
		gc.point(x, y)
	end

	gc.draw(canvas)
	canvas.write(File.join(File.dirname(__FILE__), "image.png"))
	
	html = <<EOF
		<html>
			<head>
				<script src="http://openlayers.org/api/OpenLayers.js"></script>
			</head>
			<body>
				<div style="width:100%; height:100%" id="map"></div>
				<script type="text/javascript" defer="defer">
						var map = new OpenLayers.Map('map');
						var from = new OpenLayers.Projection("EPSG:4326");
						var to = new OpenLayers.Projection("EPSG:900913");
						
						var osm_layer = new OpenLayers.Layer.OSM();
						osm_layer.setOpacity(0.3);
						map.addLayer(osm_layer);
					
						var imagebounds = new OpenLayers.Bounds(#{min_lon}, #{min_lat}, #{min_lon+max_diff}, #{min_lat+max_diff}).transform(from, to);
						var layer = new OpenLayers.Layer.Image("overlay", "image.png", imagebounds, new OpenLayers.Size(#{@config['image_size']}, #{@config['image_size']}), {alwaysInRange: true, isBaseLayer: false, transparent: true});
						map.addLayer(layer);
						map.zoomToExtent(imagebounds);
						
				</script>
			</body>
		</html>
EOF
	File.open(File.join(File.dirname(__FILE__), "image.html"), "w") {|f| f.write(html) }
end

def help
end

opt = Getopt::Long.getopts(
	['--update', '-u'],
	['--nagios', '-n'],
	['--info', '-i'],
	['--help', '-h'],
	['--graphic', '-g']
) rescue {"help"=>true}

if opt["help"] || opt.empty?
	puts <<EOF
geoloqi-backup Version #{GEOLOQI_VERSION}

  --update,  -u   Lädt neue Datensätze von Geoloqi herunter und speichert sie
                  in der MySQL-Datenbank.
  --graphic, -g   Erzeugt neue Grafiken und Kartenansichten.
  --info,    -i   Zeigt Infos über die in der Datenbank gespeicherten Einträge.
  --nagios,  -n   Gibt Daten zum Tracking via Nagios aus.
  --help,    -h   Diese Hilfe.
EOF
	exit
end

update if opt["update"]
generate_graphic if opt["graphic"]
info if opt["info"]
nagios if opt["nagios"]
