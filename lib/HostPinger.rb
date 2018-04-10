require 'logger'
require "net/http"
require "uri"
require 'json'

class HostPinger

	def initialize( ide , access_token , app_id , args = {} )
		@opt_args = {
						:protocol => "https" ,
						:logger => :info
					}.merge(args)

		setupLogger

		@endpoint = "#{ide}/api/smartapps/installations/#{app_id}"
		@log.debug("SmartThings Host Pinger Endpoint: #{@endpoint}")
		@access_token = access_token
	end

	def updateState( device , new_state )
		req = "#{@endpoint}/statechanged/#{new_state}?access_token=#{@access_token}&ipadd=#{device}"
		@log.debug "Requesting: #{req}"
		performRequest(req)
	end

	private

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

	def performRequest( req )
		uri = URI.parse(req)
		http = Net::HTTP.new(uri.host, uri.port)
		request = Net::HTTP::Get.new(uri.request_uri)

		tmp_attempts = 1
		loop do
			uri = nil
			http = nil
			request = nil

			uri = URI.parse(req)
			http = Net::HTTP.new(uri.host, uri.port)
			http.use_ssl = true if req =~ /https:\/\//
			request = Net::HTTP::Get.new(uri.request_uri)
			response = http.request(request)
			case response.code
				when "200"
					return true
				when "401"
					tmp_attempts += 1
					@log.fatal "Request FAILED (#{response.code}): #{response.body}.  Retrying..."
					sleep(RETRY_SLEEP)
				else
					@log.fatal "Request FAILED (#{response.code}): #{response.body}"
					raise "Error occured with Orbi request"
			end
			raise "Maximum attempts made." if tmp_attempts >= MAX_ATTEMPTS
		end
	end
end