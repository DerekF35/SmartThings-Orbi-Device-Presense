require 'logger'
require "net/http"
require "uri"
require 'json'
require 'terminal-table'

class Orbi
	MAX_ATTEMPTS = 3
	RETRY_SLEEP=2
	MULT_USER_SLEEP=600
	FIELDS = [ "ip" , "mac" , "contype" , "model" , "name"]
	class Device
  	attr_accessor :info
		def initialize( hsh )
			@raw = hsh
			@info = {}
			FIELDS.each do |f|
				@info[f] = @raw[f]
			end
		end

		def to_s
			return @info.to_s
		end
	end

	TABLE_HEADERS = [ "IP" , "MAC" , "ConType" , "Model" , "Name"]
	SORT = "ip"

	def initialize( host , username , password , args = {} )
		@opt_args = {
						:protocol => "http" ,
						:logger => :info ,
						:multi_login_wait => false
					}.merge(args)

		setupLogger

		@host = "#{@opt_args[:protocol]}://#{host}/"
		@username = username
		@password = password

		orbiRequest("/index.htm")
	end

	def getDevices()
		return @devices
	end

	def pullDevices()
		raw_resp = nil
		raw_resp = orbiRequest("DEV_device_info.htm")
		# get device json out of respone
		if raw_resp =~ /device=(.*)$/
			@devices = JSON.parse( $1 ).map{ |x| Device.new(x) }
			@log.debug "Raw device hash: #{@devices}"
		else
			@log.fatal "Error parsing raw response: #{raw_resp}"
			raise "Cannot get device information from pullDevices Orbi Response"
		end

	end

	def logOff()
		raw_resp = nil
		raw_resp = orbiRequest("LGO_logout.htm" )
	end

	def listDevices( deviceArr = nil  , args = {} )
		args = {
						:sort => SORT ,
						:headers => TABLE_HEADERS
					}.merge(args)

		deviceArr ||= :all
		deviceArr = @devices if deviceArr == :all

		if deviceArr.size == 0
			puts "No devices"
			return
		end

		table = Terminal::Table.new do |t|
			t << args[:headers]
			t.add_separator

			sortDevices( deviceArr , args[:sort] ).each do |d|
				tmp = []
				args[:headers].map{ |rh| rh.downcase }.each do |h|
					tmp << d.info[h]
				end
				t << tmp
			end
		end
		puts "Count: #{deviceArr.size}"
		puts table
	end

	private

	def sortDevices( devices , sort = SORT )

		case sort
			when "ip"
				return devices.sort{ |x, y| x.info[sort].split('.').map{ |octet| octet.to_i} <=>  y.info[sort].split('.').map{ |octet| octet.to_i}  }
			else
				return devices.sort{ |x, y| x.info[sort] <=> y.info[sort] }
		end
	end

	def setupLogger
		case @opt_args[:logger]
			when :info
				@log = Logger.new(STDERR)
				@log.level = Logger::INFO
			when :debug
				@log = Logger.new(STDERR)
				@log.level = Logger::DEBUG
			else
				@log = @opt_args[:logger]
		end
	end

	def orbiRequest( path , auth = true )
		req = "#{@host}/#{path}?ts=#{Time.now.to_ms}"
		@log.debug "Requesting: #{req}"

		uri = URI.parse(req)
		http = Net::HTTP.new(uri.host, uri.port)
		request = Net::HTTP::Get.new(uri.request_uri)
		request.basic_auth( @username , @password )

		tmp_attempts = 1
		loop do
			uri = nil
			http = nil
			request = nil

			uri = URI.parse(req)
			http = Net::HTTP.new(uri.host, uri.port)
			request = Net::HTTP::Get.new(uri.request_uri)
			request.basic_auth( @username , @password ) if auth

			response = http.request(request)
			case response.code
				when "200"
					if response.body =~ /multi_login.html/
						if @opt_args[:multi_login_wait]
							@log.info "Another user is logged in.  Waiting #{MULT_USER_SLEEP} minutes and retrying..."
							sleep(MULT_USER_SLEEP)
							tmp_attempts += 1
						else
							@log.info "Another user is logged in.  I will exit quietly."
							exit 0
						end
					else
						@log.debug "Request for #{path} is a success."
						@log.debug "Raw response: #{response.body}"
						return response.body
					end
				when "401"
					tmp_attempts += 1
					@log.info "Request for #{path} FAILED due to authorization. Retrying..."
					sleep(RETRY_SLEEP)
				else
					@log.fatal "Request for #{path} FAILED (#{response.code}): #{response.body}"
					raise "Error occured with Orbi request"
			end
			raise "Maximum attempts made." if tmp_attempts >= MAX_ATTEMPTS
		end

	end
end