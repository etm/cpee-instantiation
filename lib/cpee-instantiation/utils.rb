# This file is part of CPEE-INSTANTIATION
#
# CPEE-INSTANTIATION is free software: you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# CPEE-INSTANTIATION is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with CPEE-INSTANTIATION (file LICENSE in the main directory). If not, see
# <http://www.gnu.org/licenses/>.

module CPEE
  module Instantiation

    def self::watch_services(watchdog_start_off,url,path,db)
      return if watchdog_start_off
      EM.defer do
        Dir[File.join(__dir__,'routing','*.rb')].each do |s|
          s = s.sub(/\.rb$/,'')
          pid = (File.read(s + '.pid').to_i rescue nil)
          cmd = if url.nil?
            "-p \"#{path}\" -d #{db} restart"
          else
            "-u \"#{url}\" -d #{db} restart"
          end
          if (pid.nil? || !(Process.kill(0, pid) rescue false)) && !File.exist?(s + '.lock')
            system "#{s}.rb " + cmd + " 1>/dev/null 2>&1"
            puts "➡ Service #{File.basename(s)} (-v #{cmd}) started ..."
          end
        end
      end
    end

    def self::cleanup_services(watchdog_start_off)
      return if watchdog_start_off
      Dir[File.join(__dir__,'routing','*.rb')].each do |s|
        s = s.sub(/\.rb$/,'')
        pid = (File.read(s + '.pid').to_i rescue nil)
        if !pid.nil? || (Process.kill(0, pid) rescue false)
          system "#{s}.rb stop 1>/dev/null 2>&1"
          puts "➡ Service #{File.basename(s,'.rb')} stopped ..."
        end
      end
    end

  end
end
