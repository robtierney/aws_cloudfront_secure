# This is a reopenning of the same class from the right_aws gem.  http://rightaws.rubyforge.org/right_aws_gem_doc/
# Based on wiseleyb's fork: http://github.com/wiseleyb/right_aws

require 'base64'

module RightAws
  class AcfInterface

    #-----------------------------------------------------------------
    #      CLOUD DISTRIBUTION OBJECT:
    #-----------------------------------------------------------------
    class AcfDistribution

      PROTOCOL_REGEX = /\A\w+:\/\//


      # distribution             - required - url of the distribution http://d3561sl5litxcx.cloudfront.net or some cname http://images.mywebsite.com
      # key_pair_id              - required - from amazon's key creation util
      # key_pair_pem_file_name   - required - Defaults to <RAILS_ROOT>/config/cloudfront_keys/<filename> unless you give an absolute path.
      def initialize(distribution, key_pair_id, key_pair_pem_file_name)
        @distribution = distribution
        @distribution = "#{@distribution}/" unless @distribution.ends_with?("/")
        @key_pair_id = key_pair_id
        @key_pair_pem_file_name = key_pair_pem_file_name
      end

      #options
      # => resource                       required - aws key of resource to use
      # => expires                        defaults to 1 hour - you can supply a Time object or an int (seconds since epoch)
      # => ip_address                     allows you to restrict the url to IP 
      def get_private_download_url(options = {})
        [:resource].each do |k|
          raise ArgumentError if options[k].nil?
        end
        self.class.get_private_download_url(
          :resource=>options[:resource],
          :expires=>options[:expires],
          :ip_address=>options[:ip_address],
          :distribution=>@distribution,
          :key_pair_id=>@key_pair_id,
          :key_pair_pem_file_name=>@key_pair_pem_file_name
        )
      end

      # creates a expiring signed url for an object in a private distribution
      # options
      # => :distibution   cloudfront domain name or cname alias
      # => :resource      my_video.mp4
      # => :key_pair_id        key_id from amazon's key creation utility (not the EC2 one though)
      # => :key_pair_pem_file_name :: private key file for key_id (.pem) from amazon's key creation utility
      # => :expires       OPTIONAL - defaults to 1 hour, either Epoch (Unix) or Time object
      def get_private_streaming_url_for_jw_player(options = {})
        [:resource].each do |k|
          raise ArgumentError if options[k].nil?
        end
        self.class.get_private_streaming_url_for_jw_player(
          :resource=>options[:resource],
          :expires=>options[:expires],
          :distribution=>@distribution,
          :key_pair_id=>@key_pair_id,
          :key_pair_pem_file_name=>@key_pair_pem_file_name
        )
      end

      # options
      # => resource                       required - aws key of resource to use
      # => expires                        defaults to 1 hour - you can supply a Time object or an int (seconds since epoch)
      # => encode_params = false          if true this will encode params after ?
      # => prepend_file_type = true       if the resource is vid.mp4 it will create mp4:vid.mp4
      # => ip_address                     NOT IMPLEMENTED - allows you to restrict the url to one IP Address - this will require changing to a custom policy instead of canned policy.  See the non-streaming method to see how.
      def get_private_streaming_file(options = {})
        [:resource].each do |k|
          raise ArgumentError if options[k].nil?
        end
        self.class.get_private_streaming_file(
          :resource=>options[:resource],
          :expires=>options[:expires],
          :ip_address=>options[:ip_address],
          :encode_params=>options[:encode_params],
          :prepend_file_type=>options[:prepend_file_type],
          :distribution=>@distribution,
          :key_pair_id=>@key_pair_id,
          :key_pair_pem_file_name=>@key_pair_pem_file_name
        )
      end
      
      # creates an expiring streaming file + server in a hash => :file=>'mp3:Filename.mp3?Policy...', :server=>'rtmp://xxxxxx.cloudfront.net/cfx/st'
      # options
      # => resource                       required - aws key of resource to use
      # => key_pair_id                    required - from amazon's key creation util (not the EC2 one though)
      # => key_pair_pem_file_name         required - .pem file that goes with key_id
      # => expires                        defaults to 1 hour - you can supply a Time object or an int (seconds since epoch)
      # => encode_params = false          if true this will encode params after ?
      # => distribution = nil             if !nil? this will add &streamer=#{@url}/cfx/st
      # => prepend_file_type = true       if the resource is vid.mp4 it will create mp4:vid.mp4
      # => ip_address                     NOT IMPLEMENTED - allows you to restrict the url to one IP Address - this will require changing to a custom policy instead of canned policy.  See the non-streaming method to see how.
      def get_private_streaming_file_and_server(options = {})
        res = get_private_streaming_file({:prepend_file_type=>true}.merge(options))
        return {:file=>res, :server=>get_streaming_server(options)}
      end

      # returns 'rtmp://xxxxxxxxxxx.cloudfront.net/cfx/st'
      # options
      # => distribution                   optional - allows you to change the distro.
      def get_streaming_server(options={})
        self.class.get_streaming_server({:distribution=>@distribution}.merge(options))
      end

      #options
      # => distribution                   required (you can use cname if you want)
      # => resource                       required - aws key of resource to use
      # => key_pair_id                    required - from amazon's key creation util (not the EC2 one though)
      # => key_pair_pem_file_name         required - .pem file that goes with key_id
      # => expires                        defaults to 1 hour - you can supply a Time object or an int (seconds since epoch)
      # => ip_address                     allows you to restrict the url to one IP Address
      def self.get_private_download_url(options = {})
        [:distribution, :resource, :key_pair_id, :key_pair_pem_file_name].each do |k|
          raise ArgumentError if options[k].nil?
        end
        d = options[:distribution]
        expires = expires_to_i(options[:expires])
        d = "#{d}/" unless d.ends_with?("/")
        d = "http://#{d}" unless d.starts_with?("http://")
        r = options[:resource]
        r = r.reverse.chop!.reverse if r.starts_with?("/")
        r.gsub!(' ','%20')
        ip_address = options[:ip_address]
        url = "#{d}#{r}"
        sig = signature_for_resource(url, options[:key_pair_id], options[:key_pair_pem_file_name], expires, ip_address)
        policy = policy_for_resource(url, expires, ip_address)
        p = params_for_custom_policy_resource(policy, sig, options[:key_pair_id])
        "#{url}?#{p}"
      end

      # creates an expiring streaming file string
      # options
      # => resource                       required - aws key of resource to use
      # => key_pair_id                    required - from amazon's key creation util (not the EC2 one though)
      # => key_pair_pem_file_name         required - .pem file that goes with key_id
      # => expires                        defaults to 1 hour - you can supply a Time object or an int (seconds since epoch)
      # => encode_params = false          if true this will encode params after ?
      # => distribution = nil             if !nil? this will add &streamer=#{@url}/cfx/st
      # => prepend_file_type = true       if the resource is vid.mp4 it will create mp4:vid.mp4
      # => ip_address                     NOT IMPLEMENTED - allows you to restrict the url to one IP Address - this will require changing to a custom policy instead of canned policy.  See the non-streaming method to see how. 
      def self.get_private_streaming_file(options = {})
        [:resource, :key_pair_id, :key_pair_pem_file_name].each do |k|
          raise ArgumentError if options[k].nil?
        end
        resource = options[:resource]
        resource = resource.reverse.chop!.reverse if resource.starts_with?("/")
        ip_address = options[:ip_address]
        key_id = options[:key_id]  ## ??
        expires = expires_to_i(options[:expires])
        res = ""
        sig = signature_for_resource(resource, options[:key_pair_id], options[:key_pair_pem_file_name], expires, ip_address)
        options[:prepend_file_type] == true if options[:prepend_file_type].blank?
        res << "#{resource.split(".").last}:" if options[:prepend_file_type] == true
        res << (options[:prepend_file_type] ? "#{strip_file_extension(resource)}?" : "#{resource}?")
        policy = policy_for_resource(resource, expires, ip_address)  # TODO: resource might be an inadequate param, may require URL.
        # p = params_for_custom_policy_resource(policy, sig, options[:key_pair_id]) # UNTESTED!
        p = params_for_canned_policy_resource(expires, sig, options[:key_pair_id])  #TODO: make this CUSTOM, not CANNED.  CANNED is limited to expiry-date only.
        if options[:encode_params].to_s == "true"
          res << "#{url_encode(p)}"
        else
          res << p
        end
        return res
      end

      # creates a expiring signed url for an object in a private distribution
      # options
      # => :distibution   cloudfront domain name or cname alias
      # => :resource      my_video.mp4
      # => :key_pair_id        key_id from amazon's key creation utility (not the EC2 one though)
      # => :key_pair_pem_file_name :: private key file for key_id (.pem) from amazon's key creation utility (not the EC2 one though)
      # => :expires       OPTIONAL - defaults to 1 hour, either Epoch (Unix) or Time object
      def self.get_private_streaming_url_for_jw_player(options = {})
        [:distribution, :resource, :key_pair_id, :key_pair_pem_file_name].each do |k|
          raise ArgumentError if options[k].nil?
        end
        options[:prepend_file_type] = true
        options[:encode_params] = true
        "file=#{get_private_streaming_file(options)}&streamer=#{get_streaming_server(options)}"
      end

      def self.get_streaming_server(options={})
        "rtmp://#{clear_protocol(options[:distribution])}cfx/st"
      end

      protected

      def self.policy_for_resource(resource, expires = Time.now + 1.hour, ip_address=nil)
        ip_address_subpolicy = ip_address ? %("IpAddress":{"AWS:SourceIp":"#{ip_address}/24"},) : ""  # TODO: do i always want /24, or should i make that settable?
        %({"Statement":[{"Resource":"#{resource}","Condition":{#{ip_address_subpolicy}"DateLessThan":{"AWS:EpochTime":#{expires.to_i}}}}]})
      end

      def self.params_for_canned_policy_resource(expires, signature, key_pair_id)
        "Expires=#{expires.to_i}&Signature=#{signature}&Key-Pair-Id=#{key_pair_id}"
      end

      def self.params_for_custom_policy_resource(policy, signature, key_pair_id)
        "Policy=#{kill_newlines(url_safe(Base64.encode64(policy)))}&Signature=#{signature}&Key-Pair-Id=#{key_pair_id}"
      end

      def self.signature_for_resource(resource, key_id, private_key_file_name, expires = Time.now + 1.hour, ip_address=nil)
          #puts "resource: #{resource}"
          #puts "key_id (not used): #{key_id}"
          #puts "private_key_file_name: #{private_key_file_name}"
          #puts "expires: #{expires}"
          policy = policy_for_resource(resource, expires, ip_address)
          #puts "policy: #{policy}"
          key = private_key_file_contents(private_key_file_name)
          #puts "key: #{key}"
          kill_newlines(url_safe(Base64.encode64(key.sign(OpenSSL::Digest::SHA1.new, (policy)))))
      end

      def self.url_safe(str)
        str.gsub('+','-').gsub('=','_').gsub('/','~')  #.gsub(' ','')
      end

      def self.kill_newlines(str)
        str.gsub(/\n/,'')
      end

      def self.expires_to_i(e)
        expires = (Time.now + 1.hour).to_i
        if e.is_a?(Time)
          expires = e.to_i
        elsif e.to_i > 0
          expires = e.to_i
        end
        return expires
      end
      
      def self.private_key_file_contents(filename="")
        @@keys ||= {}
        return @@keys[filename] if @@keys.has_key?(filename)
        @@keys[filename] = OpenSSL::PKey::RSA.new(File.readlines(filepath_for(filename)).join("").strip)
      end

      def self.filepath_for(filename)
        absolute_path?(filename) ? filename : "#{default_private_key_path}/#{filename}"
      end

      def self.strip_file_extension(filename)
        splitup = filename.split('.')
        ext = splitup.pop if splitup.size > 1
        splitup.join('.')
      end

      def self.default_private_key_path
        Rails.root.join('config', 'cloudfront_keys')
      end

      def self.absolute_path?(string)
        string.starts_with?("/")
      end

      def self.clear_protocol(string)
        string.gsub(PROTOCOL_REGEX, '')
      end

    end

  end
end

