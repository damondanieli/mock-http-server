#!/usr/bin/env ruby
#

# Go through the fixtures directory and create a users.json file
# of users who have passed the load test suite.
#
# This is used when we record a subset of users for
# load testing but then want to issue a large number
# of requests from random concurrent users
#

require 'rubygems'
require 'json'
require 'base64'
require 'fileutils'

$stdout.sync = true # Flush after writes
$stderr.sync = true # Flush after writes

FIXTURES_DIRECTORY = 'fixtures'
ARCHIVE_DIRECTORY = 'fixtures/archive'
USERS_FILENAME = "#{FIXTURES_DIRECTORY}/users.json"
MIN_FIXTURES_PER_VALID_USER = 20
SHOW_INVALID_USERS = false

#
# Go through all response files in the fixtures directory
#

puts "Processing #{FIXTURES_DIRECTORY} directory"
requests_files = []
username_files = []
files_to_archive = []
userNameRegex = Regexp.new(/-users-userName-/)
Dir.glob("#{FIXTURES_DIRECTORY}/*.response").each do |f|
  if userNameRegex.match(f)
    username_files << f
  else
    requests_files << f
  end
end
puts "Processed #{requests_files.length + username_files.length} files"

total_users = username_files.length
if total_users == 0
  puts "No users found... exiting"
  Process.exit(1)
else
  puts "Found #{total_users} users recorded in fixtures"
end

#
# Read the user data from the */users/userName?=... request
#
# This is important because the template mechanism overrides this request
# with 
#

puts "Extracting userdata from each userName request"
userdata_array = []
username_files.each do |userNameFile|
  json = File.read(userNameFile)
  response = JSON.parse(json)
  if response['statusCode'] == 200 && response['headers'] && response['headers']['content-type'] == 'application/json'
    body = JSON.parse(Base64.decode64(response['body64']))
    userdata = body['data'][0] # This request returns an array of one user or empty array
    if userdata
      userdata_array << userdata
    else
      $stderr.puts("  File #{userNameFile} has no user data") if SHOW_INVALID_USERS
    end
  else
    $stderr.puts("  File #{userNameFile} is invalid") if SHOW_INVALID_USERS
  end
  files_to_archive << userNameFile # We archive all userName files because the template will override this request
end

total_existing_users = userdata_array.length
if total_existing_users == 0
  puts "No users found... exiting"
  Process.exit(2)
else
  puts "Found #{total_existing_users} existing users"
end
$stdout.flush()

puts "Processing users..."
users_processed = 0
username_to_id_map = {}
while users_processed < total_existing_users
  puts "#{users_processed} of #{total_existing_users}" if (users_processed % 100) == 0  
  userdata = userdata_array[users_processed]
  regex = Regexp.new(userdata['userID'].to_s)
  request_files_for_userID = []
  requests_files.delete_if do |f| 
    if regex.match(f)
      request_files_for_userID << f
      true
    end
  end
  if request_files_for_userID.length < MIN_FIXTURES_PER_VALID_USER
    $stderr.puts("  Rejecting user #{userdata['userName']} (only #{request_files_for_userID.length} requests)") if SHOW_INVALID_USERS
    files_to_archive.concat(request_files_for_userID)
  else
    username_to_id_map[userdata['userName']] = userdata['userID']
  end
  users_processed += 1
end

total_valid_users = username_to_id_map.length
if total_valid_users == 0
  puts "No users have enough fixtures for a valid test"
  Process.exit(3)
else
  puts "Found #{total_valid_users} valid users"
end

puts "Writing #{total_valid_users} users to #{USERS_FILENAME}"
File.open(USERS_FILENAME, "w") do |file|
  file.write(JSON.pretty_generate(username_to_id_map, {:indent => '  '}))
end
puts "File write to #{USERS_FILENAME} succeeded"

puts "Moving templatized and invalid files to #{ARCHIVE_DIRECTORY}"
FileUtils.mkdir_p(ARCHIVE_DIRECTORY)
files_to_archive.each do |fromFile|
  toFile = fromFile.gsub(FIXTURES_DIRECTORY, ARCHIVE_DIRECTORY)
  $stderr.puts("  Archiving #{fromFile} to #{toFile}") if SHOW_INVALID_USERS
  FileUtils.mv(fromFile, toFile)
end

puts "All templatized and invalid requests have been moved."
puts "Move files from #{ARCHIVE_DIRECTORY} to #{FIXTURES_DIRECTORY} before you run this process again"
puts "  find #{ARCHIVE_DIRECTORY}/. -name '*.response' -exec mv {} #{FIXTURES_DIRECTORY}/. \\;"
puts "Success!"
