#
# Copyright (c) 2007-2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

module RightAws

  # = RightAWS::EC2 -- RightScale Amazon EC2 interface
  # The RightAws::EC2 class provides a complete interface to Amazon's
  # Elastic Compute Cloud service, as well as the associated EBS (Elastic Block
  # Store).
  # For explanations of the semantics
  # of each call, please refer to Amazon's documentation at
  # http://developer.amazonwebservices.com/connect/kbcategory.jspa?categoryID=87
  #
  # Examples:
  #
  # Create an EC2 interface handle:
  #   
  #   @ec2   = RightAws::Ec2.new(aws_access_key_id,
  #                               aws_secret_access_key)
  # Create a new SSH key pair:
  #  @key   = 'right_ec2_awesome_test_key'
  #  new_key = @ec2.create_key_pair(@key)
  #  keys = @ec2.describe_key_pairs
  #
  # Create a security group:
  #  @group = 'right_ec2_awesome_test_security_group'
  #  @ec2.create_security_group(@group,'My awesome test group')
  #  group = @ec2.describe_security_groups([@group])[0]
  #
  # Configure a security group:
  #  @ec2.authorize_security_group_named_ingress(@group, account_number, 'default')
  #  @ec2.authorize_security_group_IP_ingress(@group, 80,80,'udp','192.168.1.0/8')
  #
  # Describe the available images:
  #  images = @ec2.describe_images
  #
  # Launch an instance:
  #  ec2.run_instances('ami-9a9e7bf3', 1, 1, ['default'], @key, 'SomeImportantUserData', 'public')
  # 
  #
  # Describe running instances:
  #  @ec2.describe_instances
  #
  # Error handling: all operations raise an RightAws::AwsError in case
  # of problems. Note that transient errors are automatically retried.
    
  class Ec2 < RightAwsBase
    include RightAwsBaseInterface
    
    # Amazon EC2 API version being used
    API_VERSION       = "2009-11-30"
    DEFAULT_HOST      = "ec2.amazonaws.com"
    DEFAULT_PATH      = '/'
    DEFAULT_PROTOCOL  = 'https'
    DEFAULT_PORT      = 443
    
    # Default addressing type (public=NAT, direct=no-NAT) used when launching instances.
    DEFAULT_ADDRESSING_TYPE =  'public'
    DNS_ADDRESSING_SET      = ['public','direct']
    
    # Amazon EC2 Instance Types : http://www.amazon.com/b?ie=UTF8&node=370375011
    # Default EC2 instance type (platform) 
    DEFAULT_INSTANCE_TYPE   =  'm1.small' 
    INSTANCE_TYPES          = ['m1.small','c1.medium','m1.large','m1.xlarge','c1.xlarge', 'm2.2xlarge', 'm2.4xlarge']
    
    @@bench = AwsBenchmarkingBlock.new
    def self.bench_xml
      @@bench.xml
    end
    def self.bench_ec2
      @@bench.service
    end
    
     # Current API version (sometimes we have to check it outside the GEM).
    @@api = ENV['EC2_API_VERSION'] || API_VERSION
    def self.api 
      @@api
    end
    
    # Create a new handle to an EC2 account. All handles share the same per process or per thread
    # HTTP connection to Amazon EC2. Each handle is for a specific account. The params have the
    # following options:
    # * <tt>:endpoint_url</tt> a fully qualified url to Amazon API endpoint (this overwrites: :server, :port, :service, :protocol and :region). Example: 'https://eu-west-1.ec2.amazonaws.com/'
    # * <tt>:server</tt>: EC2 service host, default: DEFAULT_HOST
    # * <tt>:region</tt>: EC2 region (North America by default)
    # * <tt>:port</tt>: EC2 service port, default: DEFAULT_PORT
    # * <tt>:protocol</tt>: 'http' or 'https', default: DEFAULT_PROTOCOL
    # * <tt>:multi_thread</tt>: true=HTTP connection per thread, false=per process
    # * <tt>:logger</tt>: for log messages, default: RAILS_DEFAULT_LOGGER else STDOUT
    # * <tt>:signature_version</tt>:  The signature version : '0','1' or '2'(default)
    # * <tt>:cache</tt>: true/false: caching for: ec2_describe_images, describe_instances,
    # describe_images_by_owner, describe_images_by_executable_by, describe_availability_zones,
    # describe_security_groups, describe_key_pairs, describe_addresses, 
    # describe_volumes, describe_snapshots methods, default: false.
    #
    def initialize(aws_access_key_id=nil, aws_secret_access_key=nil, params={})
      init({ :name                => 'EC2',
             :default_host        => ENV['EC2_URL'] ? URI.parse(ENV['EC2_URL']).host   : DEFAULT_HOST,
             :default_port        => ENV['EC2_URL'] ? URI.parse(ENV['EC2_URL']).port   : DEFAULT_PORT,
             :default_service     => ENV['EC2_URL'] ? URI.parse(ENV['EC2_URL']).path   : DEFAULT_PATH,
             :default_protocol    => ENV['EC2_URL'] ? URI.parse(ENV['EC2_URL']).scheme : DEFAULT_PROTOCOL,
             :default_api_version => @@api },
           aws_access_key_id    || ENV['AWS_ACCESS_KEY_ID'] , 
           aws_secret_access_key|| ENV['AWS_SECRET_ACCESS_KEY'],
           params)
    end

    def generate_request(action, params={}) #:nodoc:
      generate_request_impl(:get, action, params )
    end

      # Sends request to Amazon and parses the response
      # Raises AwsError if any banana happened
    def request_info(request, parser)  #:nodoc:
      request_info_impl(:ec2_connection, @@bench, request, parser)
    end

  #-----------------------------------------------------------------
  #      Security groups
  #-----------------------------------------------------------------

      # Retrieve Security Group information. If +list+ is omitted the returns the whole list of groups.
      #
      #  ec2.describe_security_groups #=>
      #    [{:aws_group_name  => "default-1",
      #      :aws_owner       => "000000000888",
      #      :aws_description => "Default allowing SSH, HTTP, and HTTPS ingress",
      #      :aws_perms       =>
      #        [{:owner => "000000000888", :group => "default"},
      #         {:owner => "000000000888", :group => "default-1"},
      #         {:to_port => "-1",  :protocol => "icmp", :from_port => "-1",  :cidr_ips => "0.0.0.0/0"},
      #         {:to_port => "22",  :protocol => "tcp",  :from_port => "22",  :cidr_ips => "0.0.0.0/0"},
      #         {:to_port => "80",  :protocol => "tcp",  :from_port => "80",  :cidr_ips => "0.0.0.0/0"},
      #         {:to_port => "443", :protocol => "tcp",  :from_port => "443", :cidr_ips => "0.0.0.0/0"}]},
      #    ..., {...}]
      #
    def describe_security_groups(list=[])
      link = generate_request("DescribeSecurityGroups", amazonize_list('GroupName',list.to_a))
      request_cache_or_info( :describe_security_groups, link,  QEc2DescribeSecurityGroupsParser, @@bench, list.blank?) do |parser|
        result = []     
        parser.result.each do |item|
          perms = []
          item.ipPermissions.each do |perm|
            perm.groups.each do |ngroup|
              perms << {:group => ngroup.groupName,
                        :owner => ngroup.userId}
            end
            perm.ipRanges.each do |cidr_ip|
              perms << {:from_port => perm.fromPort, 
                        :to_port   => perm.toPort, 
                        :protocol  => perm.ipProtocol,
                        :cidr_ips  => cidr_ip}
            end
          end

             # delete duplication
          perms.each_index do |i|
            (0...i).each do |j|
              if perms[i] == perms[j] then perms[i] = nil; break; end
            end
          end
          perms.compact!

          result << {:aws_owner       => item.ownerId, 
                     :aws_group_name  => item.groupName, 
                     :aws_description => item.groupDescription,
                     :aws_perms       => perms}
        
        end
        result
      end
    rescue Exception
      on_exception
    end
    
      # Create new Security Group. Returns +true+ or an exception.
      #
      #  ec2.create_security_group('default-1',"Default allowing SSH, HTTP, and HTTPS ingress") #=> true
      #
    def create_security_group(name, description)
      # EC2 doesn't like an empty description...
      description = " " if description.blank?
      link = generate_request("CreateSecurityGroup", 
                              'GroupName'        => name.to_s,
                              'GroupDescription' => description.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

      # Remove Security Group. Returns +true+ or an exception.
      #
      #  ec2.delete_security_group('default-1') #=> true
      #
    def delete_security_group(name)
      link = generate_request("DeleteSecurityGroup", 
                              'GroupName' => name.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end
    
      # Authorize named ingress for security group. Allows instances that are member of someone
      # else's security group to open connections to instances in my group.
      #
      #  ec2.authorize_security_group_named_ingress('my_awesome_group', '7011-0219-8268', 'their_group_name') #=> true
      #
    def authorize_security_group_named_ingress(name, owner, group)
      link = generate_request("AuthorizeSecurityGroupIngress", 
                              'GroupName'                  => name.to_s,
                                'SourceSecurityGroupName'    => group.to_s,
                              'SourceSecurityGroupOwnerId' => owner.to_s.gsub(/-/,''))
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end
    
      # Revoke named ingress for security group.
      #
      #  ec2.revoke_security_group_named_ingress('my_awesome_group', aws_user_id, 'another_group_name') #=> true
      #
    def revoke_security_group_named_ingress(name, owner, group)
      link = generate_request("RevokeSecurityGroupIngress", 
                              'GroupName'                  => name.to_s,
                              'SourceSecurityGroupName'    => group.to_s,
                              'SourceSecurityGroupOwnerId' => owner.to_s.gsub(/-/,''))
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end
    
      # Add permission to a security group. Returns +true+ or an exception. +protocol+ is one of :'tcp'|'udp'|'icmp'.
      #
      #  ec2.authorize_security_group_IP_ingress('my_awesome_group', 80, 82, 'udp', '192.168.1.0/8') #=> true
      #  ec2.authorize_security_group_IP_ingress('my_awesome_group', -1, -1, 'icmp') #=> true
      #
    def authorize_security_group_IP_ingress(name, from_port, to_port, protocol='tcp', cidr_ip='0.0.0.0/0')
      link = generate_request("AuthorizeSecurityGroupIngress", 
                              'GroupName'  => name.to_s,
                              'IpProtocol' => protocol.to_s,
                              'FromPort'   => from_port.to_s,
                              'ToPort'     => to_port.to_s,
                              'CidrIp'     => cidr_ip.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end
    
      # Remove permission from a security group. Returns +true+ or an exception. +protocol+ is one of :'tcp'|'udp'|'icmp' ('tcp' is default). 
      #
      #  ec2.revoke_security_group_IP_ingress('my_awesome_group', 80, 82, 'udp', '192.168.1.0/8') #=> true
      #
    def revoke_security_group_IP_ingress(name, from_port, to_port, protocol='tcp', cidr_ip='0.0.0.0/0')
      link = generate_request("RevokeSecurityGroupIngress", 
                              'GroupName'  => name.to_s,
                              'IpProtocol' => protocol.to_s,
                              'FromPort'   => from_port.to_s,
                              'ToPort'     => to_port.to_s,
                              'CidrIp'     => cidr_ip.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

  #-----------------------------------------------------------------
  #      Keys
  #-----------------------------------------------------------------
  
      # Retrieve a list of SSH keys. Returns an array of keys or an exception. Each key is
      # represented as a two-element hash.
      #
      #  ec2.describe_key_pairs #=>
      #    [{:aws_fingerprint=> "01:02:03:f4:25:e6:97:e8:9b:02:1a:26:32:4e:58:6b:7a:8c:9f:03", :aws_key_name=>"key-1"},
      #     {:aws_fingerprint=> "1e:29:30:47:58:6d:7b:8c:9f:08:11:20:3c:44:52:69:74:80:97:08", :aws_key_name=>"key-2"},
      #      ..., {...} ]
      #
    def describe_key_pairs(list=[])
      link = generate_request("DescribeKeyPairs", amazonize_list('KeyName',list.to_a))
      request_cache_or_info :describe_key_pairs, link,  QEc2DescribeKeyPairParser, @@bench, list.blank?
    rescue Exception
      on_exception
    end
      
      # Create new SSH key. Returns a hash of the key's data or an exception.
      #
      #  ec2.create_key_pair('my_awesome_key') #=>
      #    {:aws_key_name    => "my_awesome_key",
      #     :aws_fingerprint => "01:02:03:f4:25:e6:97:e8:9b:02:1a:26:32:4e:58:6b:7a:8c:9f:03",
      #     :aws_material    => "-----BEGIN RSA PRIVATE KEY-----\nMIIEpQIBAAK...Q8MDrCbuQ=\n-----END RSA PRIVATE KEY-----"}
      #
    def create_key_pair(name)
      link = generate_request("CreateKeyPair", 
                              'KeyName' => name.to_s)
      request_info(link, QEc2CreateKeyPairParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

      # Delete a key pair. Returns +true+ or an exception.
      #
      #  ec2.delete_key_pair('my_awesome_key') #=> true
      #
    def delete_key_pair(name)
      link = generate_request("DeleteKeyPair", 
                              'KeyName' => name.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end
    
  #-----------------------------------------------------------------
  #      Elastic IPs
  #-----------------------------------------------------------------

    # Acquire a new elastic IP address for use with your account.
    # Returns allocated IP address or an exception.
    #
    #  ec2.allocate_address #=> '75.101.154.140'
    #
    def allocate_address
      link = generate_request("AllocateAddress")
      request_info(link, QEc2AllocateAddressParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

    # Associate an elastic IP address with an instance.
    # Returns +true+ or an exception.
    #
    #  ec2.associate_address('i-d630cbbf', '75.101.154.140') #=> true
    #
    def associate_address(instance_id, public_ip)
      link = generate_request("AssociateAddress", 
                              "InstanceId" => instance_id.to_s,
                              "PublicIp"   => public_ip.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

    # List elastic IP addresses assigned to your account.
    # Returns an array of 2 keys (:instance_id and :public_ip) hashes:
    #
    #  ec2.describe_addresses  #=> [{:instance_id=>"i-d630cbbf", :public_ip=>"75.101.154.140"},
    #                               {:instance_id=>nil, :public_ip=>"75.101.154.141"}]
    #
    #  ec2.describe_addresses('75.101.154.140') #=> [{:instance_id=>"i-d630cbbf", :public_ip=>"75.101.154.140"}]
    #
    def describe_addresses(list=[])
      link = generate_request("DescribeAddresses", 
                              amazonize_list('PublicIp',list.to_a))
      request_cache_or_info :describe_addresses, link,  QEc2DescribeAddressesParser, @@bench, list.blank?
    rescue Exception
      on_exception
    end

    # Disassociate the specified elastic IP address from the instance to which it is assigned.
    # Returns +true+ or an exception.
    # 
    #  ec2.disassociate_address('75.101.154.140') #=> true
    #
    def disassociate_address(public_ip)
      link = generate_request("DisassociateAddress", 
                              "PublicIp" => public_ip.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

    # Release an elastic IP address associated with your account.
    # Returns +true+ or an exception.
    #
    #  ec2.release_address('75.101.154.140') #=> true
    #
    def release_address(public_ip)
      link = generate_request("ReleaseAddress", 
                              "PublicIp" => public_ip.to_s)
      request_info(link, RightBoolResponseParser.new(:logger => @logger))
    rescue Exception
      on_exception
    end

  #-----------------------------------------------------------------
  #      Availability zones
  #-----------------------------------------------------------------
    
    # Describes availability zones that are currently available to the account and their states.
    # Returns an array of 2 keys (:zone_name and :zone_state) hashes:
    #
    #  ec2.describe_availability_zones  #=> [{:region_name=>"us-east-1",
    #                                         :zone_name=>"us-east-1a",
    #                                         :zone_state=>"available"}, ... ]
    #
    #  ec2.describe_availability_zones('us-east-1c') #=> [{:region_name=>"us-east-1", 
    #                                                      :zone_state=>"available",
    #                                                      :zone_name=>"us-east-1c"}]
    #
    def describe_availability_zones(list=[])
      link = generate_request("DescribeAvailabilityZones", 
                              amazonize_list('ZoneName',list.to_a))
      request_cache_or_info :describe_availability_zones, link,  QEc2DescribeAvailabilityZonesParser, @@bench, list.blank?
    rescue Exception
      on_exception
    end

  #-----------------------------------------------------------------
  #      Regions
  #-----------------------------------------------------------------

    # Describe regions.
    #
    #  ec2.describe_regions  #=> ["eu-west-1", "us-east-1"]
    #
    def describe_regions(list=[])
      link = generate_request("DescribeRegions",
                              amazonize_list('RegionName',list.to_a))
      request_cache_or_info :describe_regions, link,  QEc2DescribeRegionsParser, @@bench, list.blank?
    rescue Exception
      on_exception
    end

  #-----------------------------------------------------------------
  #      PARSERS: Boolean Response Parser
  #-----------------------------------------------------------------
    
    class RightBoolResponseParser < RightAWSParser #:nodoc:
      def tagend(name)
        @result = @text=='true' ? true : false if name == 'return'
      end
    end

  #-----------------------------------------------------------------
  #      PARSERS: Key Pair
  #-----------------------------------------------------------------

    class QEc2DescribeKeyPairParser < RightAWSParser #:nodoc:
      def tagstart(name, attributes)
        @item = {} if name == 'item'
      end
      def tagend(name)
        case name 
          when 'keyName'        then @item[:aws_key_name]    = @text
          when 'keyFingerprint' then @item[:aws_fingerprint] = @text
          when 'item'           then @result                << @item
        end
      end
      def reset
        @result = [];    
      end
    end

    class QEc2CreateKeyPairParser < RightAWSParser #:nodoc:
      def tagstart(name, attributes)
        @result = {} if name == 'CreateKeyPairResponse'
      end
      def tagend(name)
        case name 
          when 'keyName'        then @result[:aws_key_name]    = @text
          when 'keyFingerprint' then @result[:aws_fingerprint] = @text
          when 'keyMaterial'    then @result[:aws_material]    = @text
        end
      end
    end

  #-----------------------------------------------------------------
  #      PARSERS: Security Groups
  #-----------------------------------------------------------------

    class QEc2UserIdGroupPairType #:nodoc:
      attr_accessor :userId
      attr_accessor :groupName
    end

    class QEc2IpPermissionType #:nodoc:
      attr_accessor :ipProtocol
      attr_accessor :fromPort
      attr_accessor :toPort
      attr_accessor :groups
      attr_accessor :ipRanges
    end

    class QEc2SecurityGroupItemType #:nodoc:
      attr_accessor :groupName
      attr_accessor :groupDescription
      attr_accessor :ownerId
      attr_accessor :ipPermissions
    end

    class QEc2DescribeSecurityGroupsParser < RightAWSParser #:nodoc:
      def tagstart(name, attributes)
        case name
          when 'item' 
            if @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo'
              @group = QEc2SecurityGroupItemType.new 
              @group.ipPermissions = []
            elsif @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo/item/ipPermissions'
              @perm = QEc2IpPermissionType.new
              @perm.ipRanges = []
              @perm.groups   = []
            elsif @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo/item/ipPermissions/item/groups'
              @sgroup = QEc2UserIdGroupPairType.new
            end
        end
      end
      def tagend(name)
        case name
          when 'ownerId'          then @group.ownerId   = @text
          when 'groupDescription' then @group.groupDescription = @text
          when 'groupName'
            if @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo/item'
              @group.groupName  = @text 
            elsif @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo/item/ipPermissions/item/groups/item'
              @sgroup.groupName = @text 
            end
          when 'ipProtocol'       then @perm.ipProtocol = @text
          when 'fromPort'         then @perm.fromPort   = @text
          when 'toPort'           then @perm.toPort     = @text
          when 'userId'           then @sgroup.userId   = @text
          when 'cidrIp'           then @perm.ipRanges  << @text
          when 'item'
            if @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo/item/ipPermissions/item/groups'
              @perm.groups << @sgroup
            elsif @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo/item/ipPermissions'
              @group.ipPermissions << @perm
            elsif @xmlpath=='DescribeSecurityGroupsResponse/securityGroupInfo'
              @result << @group
            end
        end
      end
      def reset
        @result = []
      end
    end

  #-----------------------------------------------------------------
  #      PARSERS: Elastic IPs
  #-----------------------------------------------------------------
  
    class QEc2AllocateAddressParser < RightAWSParser #:nodoc:
      def tagend(name)
        @result = @text if name == 'publicIp'
      end
    end
    
    class QEc2DescribeAddressesParser < RightAWSParser #:nodoc:
      def tagstart(name, attributes)
        @address = {} if name == 'item'
      end
      def tagend(name)
        case name
        when 'instanceId' then @address[:instance_id] = @text.blank? ? nil : @text 
        when 'publicIp'   then @address[:public_ip]   = @text
        when 'item'       then @result << @address
        end
      end
      def reset
        @result = []
      end
    end

  #-----------------------------------------------------------------
  #      PARSERS: AvailabilityZones
  #-----------------------------------------------------------------

    class QEc2DescribeAvailabilityZonesParser < RightAWSParser #:nodoc:
      def tagstart(name, attributes)
        @zone = {} if name == 'item'
      end
      def tagend(name)
        case name
        when 'regionName' then @zone[:region_name] = @text
        when 'zoneName'   then @zone[:zone_name]   = @text
        when 'zoneState'  then @zone[:zone_state]  = @text
        when 'item'       then @result << @zone
        end
      end
      def reset
        @result = []
      end
    end

  #-----------------------------------------------------------------
  #      PARSERS: Regions
  #-----------------------------------------------------------------

    class QEc2DescribeRegionsParser < RightAWSParser #:nodoc:
      def tagend(name)
        @result << @text if name == 'regionName'
      end
      def reset
        @result = []
      end
    end
    
  end
      
end
