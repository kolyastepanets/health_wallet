# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This application keeps all of its domain data in MongoDB via Mongoid. Active
# Record is only used for the Solid Cache/Queue/Cable infrastructure, which lives
# in its own production databases (see config/database.yml). The primary database
# therefore has no tables, so this schema is intentionally empty. It is committed
# so the test suite's parallel database setup has a schema to load.

ActiveRecord::Schema[8.1].define(version: 0) do
end
