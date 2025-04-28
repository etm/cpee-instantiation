# This file is part of CPEE-INSTANTIATION.
#
# CPEE-INSTANTIATION is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# CPEE-INSTANTIATION is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License
# for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with CPEE-INSTANTIATION (file LICENSE in the main directory).  If not,
# see <http://www.gnu.org/licenses/>.

require 'rubygems'
require 'cpee/value_helper'
require 'cpee/redis'
require 'xml/smart'
require 'riddl/server'
require 'securerandom'
require 'base64'
require 'uri'
require 'redis'
require 'json'

require_relative 'utils'

module CPEE
  module Instantiation

    SERVER = File.expand_path(File.join(__dir__,'instantiation.xml'))

    module Helpers #{{{

      def add_to_testset(tdoc,what,data) #{{{
        if data && !data.empty?
          JSON::parse(data).each do |k,v|
            ele = tdoc.find("/*/prop:#{what}/prop:#{k}")
            if ele.any?
              ele.first.text = CPEE::ValueHelper::generate(v)
            else
              ele = tdoc.find("/*/prop:#{what}")
              ele = if ele.any?
                ele.first
              else
                tdoc.root.add("prop:#{what}")
              end
              ele.add(k,CPEE::ValueHelper::generate(v))
            end
          end
        end
      end #}}}

      def augment_testset(tdoc,p) #{{{
        tdoc = XML::Smart.string(tdoc)
        tdoc.register_namespace 'desc', 'http://cpee.org/ns/description/1.0'
        tdoc.register_namespace 'prop', 'http://cpee.org/ns/properties/2.0'
        tdoc.register_namespace 'sub', 'http://riddl.org/ns/common-patterns/notifications-producer/2.0'

        if data = p.find{ |e| e.name == 'init' }&.value
          add_to_testset(tdoc,'dataelements',data)
        end
        if data = p.find{ |e| e.name == 'endpoints' }&.value
          add_to_testset(tdoc,'endpoints',data)
        end
        if data = p.find{ |e| e.name == 'attributes' }&.value
          add_to_testset(tdoc,'attributes',data)
        end
        tdoc
      end #}}}

      def customize_testset(customization,doc) #{{{
        if customization && !customization.empty?
          JSON.parse(customization).each do |e|
            begin
              customization = Typhoeus.get e['url']
              if customization.success?
                XML::Smart::string(customization.response_body) do |str|
                  doc.find("//desc:call[@id=\"#{e['id']}\"]/desc:parameters/desc:customization").each do |ele|
                    ele.replace_by str.root
                  end
                end
              end
            rescue => e
              puts e.message
              puts e.backtrace
            end
          end
        end
      end   #}}}

      def add_waiting_to_testset(behavior,cb,doc,selfurl) #{{{
        ckb = nil
        if behavior =~ /^wait/
          condition = behavior.match(/_([^_]+)_/)&.[](1) || 'finished'

          if cb
            cbk = 'instantiation_' + Digest::MD5.hexdigest(Kernel::rand().to_s)
            n = doc.find('/*/sub:subscriptions') rescue []
            if (n.empty?)
              n = doc.root.add('subscriptions')
              n.namespaces.add(nil,'http://riddl.org/ns/common-patterns/notifications-producer/2.0')
            else
              n = n.first
            end
            n.append('subscription', :id => cbk, :url => File.join(selfurl,'callback',cbk))
             .append('topic', :id => 'state')
             .append('event','change')
          end
        end
        [cbk, condition]
      end   #}}}

      def add_running_to_testset(behavior,doc) #{{{
        if behavior =~ /_running$/
          if ((doc.find('/*/prop:state')).empty?)
            doc.root.append('prop:state','running')
          else
            doc.find('/*/prop:state').first.text = 'running'
          end
        end
      end   #}}}

      def instantiate_testset(cpee,doc,behavior,cblist,cbk,cb,condition) #{{{
        status, res, headers = Riddl::Client.new(cpee).post Riddl::Parameter::Complex.new('testset', 'application/xml', doc.to_s)
        if status == 200
          instance = res.first.value
          uuid = headers['CPEE_INSTANCE_UUID']

          if cbk
            cblist.rpush(cbk, cb)
            cblist.rpush(cbk, condition)
            cblist.rpush(cbk, instance)
            cblist.rpush(cbk, uuid)
            cblist.rpush(cbk, File.join(cpee,instance))
            @headers << Riddl::Header.new('CPEE-CALLBACK','true')
          end

          send = {
            'CPEE-INSTANCE' => instance,
            'CPEE-INSTANCE-URL' => File.join(cpee,instance),
            'CPEE-INSTANCE-UUID' => uuid,
            'CPEE-BEHAVIOR' => behavior
          }
          @headers << Riddl::Header.new('CPEE-INSTANTIATION',JSON::generate(send))
          Riddl::Parameter::Complex.new('instance','application/json',JSON::generate(send))
        else
          @status = 500
        end
      end #}}}

    end #}}}

    class InstantiateGit < Riddl::Implementation #{{{
      include Helpers

      def response
        cpee     = @h['X_CPEE'] || @a[0]
        selfurl  = @a[1]
        cblist   = @a[2]
        behavior = @p[0].value

        status, res = Riddl::Client.new(File.join(@p[1].value,'raw',@p[2].value,@p[3].value).gsub(/ /,'%20')).get
        tdoc = if status >= 200 && status < 300
          res[0].value.read
        else
          (@status = 500) && return
        end
        customization = @p.find{ |e| e.name == 'customization' }&.value

        doc = augment_testset(tdoc,@p)
        customize_testset(customization,doc)
        cbk, condition = add_waiting_to_testset(behavior,@h['CPEE_CALLBACK'],doc,selfurl)
        add_running_to_testset(behavior,doc)

        instantiate_testset(cpee,doc,@p[0].value,cblist,cbk,@h['CPEE_CALLBACK'],condition)
      end
    end  #}}}

    class InstantiateUrl < Riddl::Implementation #{{{
      include Helpers

      def response
        cpee     = @h['X_CPEE'] || @a[0]
        selfurl  = @a[1]
        cblist   = @a[2]
        name     = @a[3] ? @p.shift.value : nil
        behavior = @p[0].value

        status, res = Riddl::Client.new(@p[1].value.gsub(/ /,'%20')).get
        tdoc = if status >= 200 && status < 300
          res[0].value.read
        else
          (@status = 500) && return
        end
        customization = @p.find{ |e| e.name == 'customization' }&.value

        doc = augment_testset(tdoc,@p)
        customize_testset(customization,doc)
        cbk, condition = add_waiting_to_testset(behavior,@h['CPEE_CALLBACK'],doc,selfurl)
        add_running_to_testset(behavior,doc)

        instantiate_testset(cpee,doc,@p[0].value,cblist,cbk,@h['CPEE_CALLBACK'],condition)
      end
     end  #}}}

    class InstantiateXML < Riddl::Implementation #{{{
      include Helpers

      def response
        cpee     = @h['X_CPEE'] || @a[0]
        behavior = @a[1] ? 'fork_ready' : @p[0].value
        data     = @a[1] ? 0 : 1
        selfurl  = @a[2]
        cblist   = @a[3]
        tdoc = if @p[data].additional =~ /base64/
          Base64.decode64(@p[data].value.read)
        else
          @p[data].value.read
        end

        doc = augment_testset(tdoc,@p)
        cbk, condition = add_waiting_to_testset(behavior,@h['CPEE_CALLBACK'],doc,selfurl)
        add_running_to_testset(behavior,doc)

        instantiate_testset(cpee,doc,@p[0].value,cblist,cbk,@h['CPEE_CALLBACK'],condition)
      end
    end #}}}

    class ContinueTask < Riddl::Implementation #{{{
      def response
        cblist       = @a[1]
        topic        = @p[1].value
        event_name   = @p[2].value
        notification = if @p[3].class === Riddl::Parameter::Simple
          JSON.parse(@p[3].value)
        else
          JSON.parse(@p[3].value.read)
        end

        key = @r.last
        cb, condition, instance, uuid, instance_url = cblist.lrange(key,0,-1)

        return if cb.nil?

        cpee = File.dirname(instance_url)

        send = {
          'CPEE-INSTANCE' => instance,
          'CPEE-INSTANCE-URL' => instance_url,
          'CPEE-INSTANCE-UUID' => uuid,
          'CPEE-STATE' => notification['content']['state']
        }

        if notification['content']['state'] == condition
          cblist.del(key)
          srv = Riddl::Client.new(cpee)
          res = srv.resource("/#{instance}/properties/dataelements")
          status, response = res.get
          if status >= 200 && status < 300
            doc = XML::Smart.string(response[0].value.read)
            doc.register_namespace 'p', 'http://cpee.org/ns/properties/2.0'
            doc.find('/p:dataelements/*').each do |e|
              send[e.qname.name] = CPEE::ValueHelper::parse(e.text)
            end
          end
          Riddl::Client.new(cb).put Riddl::Parameter::Complex.new('dataelements','application/json',JSON::generate(send))
        else
          Riddl::Client.new(cb).put [
            Riddl::Header.new('CPEE-UPDATE','true'),
            Riddl::Parameter::Complex.new('dataelements','application/json',JSON::generate(send))
          ]
        end
      end

    end #}}}

    def self::implementation(opts)
      opts[:cpee]       ||= 'http://localhost:9298/'
      opts[:self]       ||= "http#{opts[:secure] ? 's' : ''}://#{opts[:host]}:#{opts[:port]}/"

      opts[:watchdog_frequency]         ||= 7
      opts[:watchdog_start_off]         ||= false

      ### set redis_cmd to nil if you want to do global
      ### at least redis_path or redis_url and redis_db have to be set if you do global
      opts[:redis_path]                 ||= 'redis.sock' # use e.g. /tmp/redis.sock for global stuff. Look it up in your redis config
      opts[:redis_db]                   ||= 0
      ### optional redis stuff
      opts[:redis_url]                  ||= nil
      opts[:redis_cmd]                  ||= 'redis-server --port 0 --unixsocket #redis_path# --unixsocketperm 600 --pidfile #redis_pid# --dir #redis_db_dir# --dbfilename #redis_db_name# --databases 1 --save 900 1 --save 300 10 --save 60 10000 --rdbcompression yes --daemonize yes'
      opts[:redis_pid]                  ||= 'redis.pid' # use e.g. /var/run/redis.pid if you do global. Look it up in your redis config
      opts[:redis_db_name]              ||= 'redis.rdb' # use e.g. /var/lib/redis.rdb for global stuff. Look it up in your redis config

      CPEE::redis_connect opts, 'Instantiation'

      Proc.new do
        parallel do
          CPEE::Instantiation::watch_services(opts[:watchdog_start_off],opts[:redis_url],File.join(opts[:basepath],opts[:redis_path]),opts[:redis_db])
          EM.add_periodic_timer(opts[:watchdog_frequency]) do ### start services
            CPEE::Instantiation::watch_services(opts[:watchdog_start_off],opts[:redis_url],File.join(opts[:basepath],opts[:redis_path]),opts[:redis_db])
          end
        end

        on resource do
          run InstantiateXML, opts[:cpee], true if post 'xmlsimple'
          on resource 'xml' do
            run InstantiateXML, opts[:cpee], false if post 'xml'
          end
          on resource 'url' do
            run InstantiateUrl, opts[:cpee], opts[:self], opts[:redis], false if post 'url'
            run InstantiateUrl, opts[:cpee], opts[:self], opts[:redis], true  if post 'url_info'
          end
          on resource 'git' do
            run InstantiateGit, opts[:cpee], opts[:self], opts[:redis] if post 'git'
          end
          on resource 'callback' do
            on resource do
              run ContinueTask, opts[:cpee], opts[:redis] if post
            end
          end
        end
      end
    end

  end
end
