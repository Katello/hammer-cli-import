# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=ruby
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

