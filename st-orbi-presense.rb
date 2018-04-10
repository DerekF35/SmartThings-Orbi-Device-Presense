#!/usr/bin/env ruby

##################
## INCLUDES
##################

INCLUDES_DIR="#{__dir__}/lib/"

require 'optparse'
require 'logger'
require 'yaml'

Dir["#{INCLUDES_DIR}/*.rb"].each {|file| require_relative file }

##################
## INITIALIZE
##################

log = Logger.new(STDERR)
log.level = Logger::INFO

args = {
	:config => "#{__dir__}/config.yml" ,
	:commit => true,
	:force_update => false,
	:process => false,
	:list => false,
	:sort => "ip",
	:latest_status => "#{__dir__}/latest_status.yml"
}

SORTS = [ "ip" , "mac" , "contype" , "model" , "name" ]

# initialize processes rules
processed_rules = {}
ping_status = {}

##################
## GET INPUTS
##################

parser = OptionParser.new do|opts|
  opts.banner = "Usage: #{__FILE__} [options]"

  opts.on( "-p", "--process"  , "Process rules and update Host Pinger on SmartThings." ) do
		args[:process] = true
  end

  opts.on( "-l", "--list"  , "List all devices." ) do
		args[:list] = true
  end

  opts.on( "-f", "--force"  ,"Force a single run with an update of each device state." ) do
		args[:force_update] = true
  end

  opts.on( "", "--config input"  ,"Configuration file to pull the configuration from. (Default: #{args[:config]})" ) do | input |
  	args[:config] = input
  end

  opts.on( "", "--status-file input"  ,"Yaml file to save the host statuses in for use run to run.  If it does not exist, it will be created.  (Default: #{args[:latest_status]})" ) do | input |
  	args[:latest_status] = input
  end

  opts.on( "-s", "--sort input"  , "Field (ip, mac, contype, model, name) to sort device tables on.  ( Default: #{args[:sort]} ) " ) do |input|
		args[:sort] = input
  end

  opts.on( "-t", "--test"  ,"Enable test/dry run mode.  No 'write' actions will be performed." ) do
		args[:commit] = false
  end

  opts.on( "-d", "--debug"  ,"Enable debug logging." ) do
		log.level = Logger::DEBUG
  end

  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end

end

parser.parse!

log.debug("Inputs: #{$args}")

raise "An action is required.  Please supply --list or --process" unless args[:list] || args[:process]
raise "#{args[:sort]} is not a valid sort option." unless SORTS.include?( args[:sort] )

if !File.exists?(args[:config])
	log.fatal "Configuration file (#{args[:config]}) does not exist."
	raise "No configuration file."
end

config = YAML.load_file( args[:config] )

log.debug "Loaded configuration file: #{config}"

# Setup orbi class instance with paramters
orbi = Orbi.new( config[:orbi_host] , config[:orbi_username] , config[:orbi_password] , { :logger => log } )
host_pinger = HostPinger.new( config[:smartthings_ide] , config[:host_pinger_access_token] , config[:host_pinger_app_id]  , { :logger => log } )

# set all rules to unknown status
( config[:rules] || {} ).each{ |r,i| ping_status[r] = :unknown }

if File.exists?(args[:latest_status])
	log.info "Loading latest status file ( #{args[:latest_status]} )..."
	ping_status.merge!( YAML.load_file(args[:latest_status]) )
	log.info "New ping status: #{ping_status}"
end

# Pull list of devices from Orbi router
log.info "Pulling Devices from Orbi..."
orbi.pullDevices
log.info "..devices pulled successfully."

log.info "Logging off Orbi..."
orbi.logOff
log.info "...Orbi logoff successful."

log.info "Processing rules..."
# clear processed rules variables
processed_rules = {}

# Process each rule.  Add to processed rules if pattern matches.
( config[:rules] || {} ).each do |r,i|
	log.debug "Processing rule #{r}. Field: #{i[:field]} Pattern: #{i[:pattern]}"
	processed_rules[r] ||= []
	orbi.getDevices.each do |d|
		if d.info[i[:field]]  =~ /#{i[:pattern]}/
			log.debug "MATCH on device #{d}"
			processed_rules[r] << d
		else
			log.debug "No match on device #{d}"
		end
	end
end
log.info "...rules processed successfully."

# LIST DEVICES
if args[:list]
	( config[:rules] || {} ).each do |r,i|
		tmp_t = "Rule: #{r} (Field: #{i[:field]} Pattern: /#{i[:pattern]}/ )"
		puts
		puts tmp_t
		puts tmp_t.size.times.map{|x| "-"}.join
		orbi.listDevices( processed_rules[r] || [] , { :sort => args[:sort] } )
		puts
	end

	tmp_t = "ALL DEVICES"
	puts
	puts tmp_t
	puts tmp_t.size.times.map{|x| "-"}.join
	orbi.listDevices( :all , { :sort => args[:sort] })
	puts
end

# PROCESS ALL RULES AND SEND TO SMARTTHINGS
if args[:process]
	processed_rules.each do |r,d|
		log.info "[#{r}] Determining status of rule"
		tmp_status = nil
		if d.size == 0
			log.info "[#{r}] No active devices found."
			tmp_status = :offline
		else
			log.info "[#{r}] #{d.size} active devices found!"
			tmp_status = :online
		end

		if tmp_status != ping_status[r] || args[:force_update]
			ping_status[r] = tmp_status
			log.info "[#{r}] Device status change detected.  Performing update..."
			host_pinger.updateState( r , ping_status[r] ) if args[:commit]
		else
			log.info "[#{r}] Device status NOT changed."
		end
	end

	log.info "Writing lastest status to #{args[:latest_status]}"

	File.open( args[:latest_status] ,'w') do |f|
		f.write ping_status.to_yaml
	end
end
