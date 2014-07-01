# We provide the output of this process in the distribution of the tool - this code exists
# only if someone wants to do their own mapping (?!?)
#
# Fun heuristics below
#
# cdn-map file is JSON, [{'channel'=>c, 'path'=>p},...]
# In 'path', if we can find the 'basearch', we can (usually) derive the
# right 'releasever' - path-fmt is .../$releasever/$basearch...'
# solaris breaks things - skip it
# fasttrack has no $releasever
# repo-set-urls don't end in /Package
#
# Return a map keyed by channel-label, returns map of
#   {url, version, arch, set-url}
# We should be able to match set-url to repo-set['url']
# Fun!
def read_channel_map(filename)
  rc = {}
  parsed = ''
  File.open(filename, 'r') do |f|
    json = f.read
    # [ {'channel', 'path'}...]
    parsed = JSON.parse(json)
  end

  archs = %w(i386 x86_64 s390x s390 ppc64 ppc ia64)
  parsed.each do |c|
    path_lst = c['path'].split('/')
    arch_ndx = path_lst.index { |a| archs.include?(a) }
    if arch_ndx.nil?
      puts 'Arch not found: [' + c['path'] + '], skipping...'
      next
    end
    vers_ndx = arch_ndx - 1
    channel_data = {
      'url' => c['path'],
      'version' => path_lst[vers_ndx],
      'arch' => path_lst[arch_ndx]
    }
    path_lst[arch_ndx] = '$basearch'
    path_lst[vers_ndx] = '$releasever' unless path_lst[1] == 'fastrack'
    repo_set_url = path_lst[0..-2].join('/')
    channel_data['set-url'] = repo_set_url
    rc[c['channel']] = channel_data
  end

  return rc
end
