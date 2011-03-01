#!/usr/bin/env ruby
#    Rubyripper - A secure ripper for Linux/BSD/OSX
#    Copyright (C) 2007 - 2010  Bouke Woudstra (boukewoudstra@gmail.com)
#
#    This file is part of Rubyripper. Rubyripper is free software: you can
#    redistribute it and/or modify it under the terms of the GNU General
#    Public License as published by the Free Software Foundation, either
#    version 3 of the License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>

# class that gets the freedb string
class FreedbString
attr_reader :freedbString, :discid

  # setup some references to needed objects
  def initialize(dependency, preferences, scanDiscCdparanoia, fireCommand, scanDiscCdinfo)
    @deps = dependency
    @prefs = preferences
    @disc = scanDiscCdparanoia
    @fire = fireCommand
    @cdinfo = scanDiscCdinfo
  end

  # fetch the freedb string
  def freedbString
    @freedbString ||= getFreedbString
  end

  # fetch the discid
  def discid
    @discid ||= getDiscId
  end

private

  def getFreedbString
    get()
    @freedbString
  end

  def getDiscId
    get()
    @discid
  end

  # try to get the freedbstring
  def get
    autoCalcFreedb()

    if @freedbString.nil?
      if @prefs.get('debug')
        puts _("warning: discid or cd-discid isn't found on your system!)")
        puts _("Using fallback...")
      end
      manualCalcFreedb()
    else
      @discid = @freedbString.split()[0]
    end
  end



  # try to fetch freedb string with help programs
  def autoCalcFreedb
    unmountDiscDarwin() if @deps.platform.include?('darwin')

    if @deps.installed?('discid')
      @freedbString = @fire.launch("discid #{@prefs.get('cdrom')}")
    elsif @deps.installed?('cd-discid')
      @freedbString = @fire.launch("cd-discid #{@prefs.get('cdrom')}")
    end

    remountDiscDarwin() if @deps.platform.include?('darwin')
  end

  # mac OS needs to unmount the disc first
  def unmountDiscDarwin
      @fire.launch("diskutil unmount #{@prefs.get('cdrom')}")
  end

  # mac OS needs to mount the disc again
  def remountDiscDarwin
     @fire.launch("diskutil mount #{@prefs.get('cdrom')}")
  end

  # try to calculate it ourselves
  def manualCalcFreedb
    @startSector = @disc.get('startSector')
    @lengthSector = @disc.get('lengthSector')
    @audiotracks = @lengthSector.keys.length

    # cd-info get us more reliable disc info
    tryCdinfo()
    setDiscId()
    buildFreedbString()
  end

  # Cd-info reads the toc more reliably than cdparanoia
  def tryCdinfo
    if @deps.installed?('cd-info')
      @cdinfo.scan
      if @cdinfo.status == 'ok'
        @startSector = @cdinfo.get('startSector')
        @lengthSector = @cdinfo.get('lengthSector')
        @audiotracks = @cdinfo.get('tracks')
      end
    end
  end

  # The freedb checksum is calculated as follows:
  # * for each track determine the amount of seconds it starts (offset=150)
  # * then count the individual numbers up to the total
  # * For example if seconds = 338 seconds, total is added with 3+3+8=14
  def setChecksum
    total = 0
    @startSector.keys.sort.each do |track|
      seconds = (@startSector[track] + 150) / 75
      seconds.to_s.split(/\s*/).each{|s| total += s.to_i}
    end

    return total
  end

  # Calculate the discid using some magic which make my brain hurt itself
  def setDiscId
    @totalSectors = @startSector[@audiotracks] - @startSector[1]
    @totalSectors += @lengthSector[@audiotracks]

    @totalSeconds = @totalSectors / 75

    @discid = ((setChecksum() % 0xff) << 24 | @totalSeconds << 8 | @audiotracks).to_s(16)
    @discid.upcase!
  end

  # now build the freedb string
  # this consists of:
  # * discid
  # * amount of tracks
  # * each starting sector, corrected with 150 offset
  # * total seconds of playtime
  def buildFreedbString
    @freedbString = String.new
    @freedbString << "#{@discid} "
    @freedbString << "#{@audiotracks} "

    @startSector.keys.sort.each do |key|
      @freedbString << "#{@startSector[key] + 150} "
    end

    @freedbString << "#{(@totalSectors + 150) / 75}"
  end
end