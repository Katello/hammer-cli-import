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

require 'test/unit'
require './deltahash'

class TestDeltaHash < Test::Unit::TestCase
  def test_simple
    dh = DeltaHash.new({})
    assert_equal({}, dh.to_h)
    dh[1] = :a
    assert_equal({1 => :a}, dh.to_h)
    assert_equal(:a, dh[1])
  end

  def test_new
    dh = DeltaHash[{:a => 1, :b => 2}]
    dh[:c] = 3
    assert_equal({:c => 3}, dh.new)
  end

  def test_existing
    dh = DeltaHash[{:a => 1, :b => 2}]
    assert_raise(DeltaHashError) { dh[:b] = 2 }
  end

  def test_delete
    dh = DeltaHash[{:a => 1, :b => 2}]
    assert_raise(DeltaHashError) { dh.delete :c }

    dh.delete :a
    assert_equal({:b => 2}, dh.to_h)
    assert_equal([:a], dh.del.to_a)
    assert_equal({}, dh.new)
    assert_raise(DeltaHashError) { dh.delete :a }

    dh[:a] = 1
    assert_equal({:a => 1, :b => 2}, dh.to_h)
    assert_equal([], dh.del.to_a)
    assert_equal({}, dh.new)

    dh.delete :a
    dh[:a] = 2
    assert_equal({:a => 2, :b => 2}, dh.to_h)
    assert_equal([], dh.del.to_a)
    assert_equal({:a => 2}, dh.new)
  end
end
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
