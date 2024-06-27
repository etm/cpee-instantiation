Gem::Specification.new do |s|
  s.name             = "cpee-instantiation"
  s.version          = "1.0.20"
  s.platform         = Gem::Platform::RUBY
  s.license          = "LGPL-3.0"
  s.summary          = "Subprocess instantiation service for the cloud process execution engine (cpee.org)"

  s.description      = "see http://cpee.org"

  s.files            = Dir['{server/**/*,tools/**/*,lib/**/*}'] + %w(LICENSE Rakefile cpee-instantiation.gemspec README.md AUTHORS)
  s.require_path     = 'lib'
  s.extra_rdoc_files = ['README.md']
  s.bindir           = 'tools'
  s.executables      = ['cpee-instantiation']

  s.required_ruby_version = '>=2.4.0'

  s.authors          = ['Juergen eTM Mangler', 'Heinrich Fenkart']

  s.email            = 'juergen.mangler@gmail.com'
  s.homepage         = 'http://cpee.org/'

  s.add_runtime_dependency 'riddl', '~> 1.0'
  s.add_runtime_dependency 'json', '~> 2.1'
  s.add_runtime_dependency 'redis', '~> 5.0'
  s.add_runtime_dependency 'cpee', '~> 2.1', '>= 2.1.4'
end
