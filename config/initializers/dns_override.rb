require 'resolv'
require 'resolv-replace'

dns = Resolv::DNS.new(nameserver: ['8.8.8.8', '1.1.1.1'], search: [], ndots: 1)
dns.timeouts = [2, 2, 4]
Resolv::DefaultResolver.replace_resolvers([Resolv::Hosts.new, dns])
