# Rails.cache has been pointed at :solid_cache_store in production since the app
# was generated, but nothing ever created the table it reads and writes.
#
# db/cache_schema.rb defines it, and db:prepare loads that file only when it
# creates the cache database -- here all four databases in config/database.yml
# share one DATABASE_URL, so the database already existed and the schema was
# never loaded. The Solid Queue tables reached production the same way and
# their absence took Puma down with it, so this is the same failure waiting on
# the first line of code to call Rails.cache.
#
# Table definition copied from db/cache_schema.rb; if_not_exists keeps this
# harmless anywhere db:prepare did get there first.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_cache_entries, if_not_exists: true do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false

      t.index :byte_size
      t.index [:key_hash, :byte_size]
      t.index :key_hash, unique: true
    end
  end
end
