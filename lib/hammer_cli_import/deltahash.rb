#
# Copyright (c) 2014 Red Hat Inc.
#
# This file is part of hammer-cli-import.
#
# hammer-cli-import is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# hammer-cli-import is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with hammer-cli-import.  If not, see <http://www.gnu.org/licenses/>.
#

require 'set'

class DeltaHashError < RuntimeError
end

class DeltaHash
  attr_reader :new
  attr_reader :del

  def self.[](hash)
    new(hash)
  end

  def initialize(hash)
    @old = hash
    @new = {}
    @del = Set.new
  end

  def [](key)
    return nil if @del.include? key
    @new[key] || @old[key]
  end

  def []=(key, val)
    fail DeltaHashError, 'Key exists' if self[key]
    @del.delete key
    @new[key] = val unless @old[key] == val
  end

  def to_hash
    ret = (@old.merge @new)
    @del.each do |key|
      ret.delete key
    end
    ret
  end

  def delete(key)
    fail DeltaHashError, "Key #{key} does not exist" unless self[key]
    @del << key if @old[key]
    @new.delete(key)
  end

  def delete_value(value)
    deleted = 0
    to_hash.each do |k, v|
      next unless v == value
      delete(k)
      deleted += 1
    end
    return deleted
  end

  def to_s
    to_hash.to_s
  end

  def inspect
    to_hash.inspect
  end

  def changed?
    ! (@new.empty? && del.empty?)
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
