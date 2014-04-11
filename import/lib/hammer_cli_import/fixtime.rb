class Time
  def iso8601
    strftime '%Y-%m-%dT%H:%M:%S%z'
  end
end
