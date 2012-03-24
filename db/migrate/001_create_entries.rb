class CreateEntries < ActiveRecord::Migration

	def self.up
	  create_table "entries", :force => true, :options => "ENGINE=MyISAM" do |t|
		t.datetime "date",                                                  :null => false
		t.column   "uuid",      "char(36)",                               :null => false
		t.decimal  "latitude",                :precision => 8, :scale => 5, :null => false
		t.decimal  "longitude",               :precision => 8, :scale => 5, :null => false
		t.integer  "speed",     :limit => 2,                                :null => false
		t.integer  "altitude",  :limit => 2,                                :null => false
		t.integer  "heading",   :limit => 2,                                :null => false
		t.integer  "accuracy",  :limit => 2,                                :null => false
		t.integer  "battery",   :limit => 1
	  end

	  add_index "entries", ["accuracy", "latitude", "longitude"], :name => "box"
	  add_index "entries", ["date"], :name => "date"
	  add_index "entries", ["latitude"], :name => "latitude"
	  add_index "entries", ["longitude"], :name => "longitude"
	end

	def self.down
		drop_table "entries"
	end

end
