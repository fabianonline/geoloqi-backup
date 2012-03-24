require 'geoloqi-backup'
require "sinatra/activerecord/rake"

namespace :cache do
	desc "Clears the image_cache"
	task :clear do
		FileUtils.rm_r(Dir.glob(File.join(File.dirname(__FILE__), "public", "image_cache", "*")))
	end
end
