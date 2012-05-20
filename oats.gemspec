# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "oats/version"

Gem::Specification.new do |s|
  s.name        = "oats"
  s.version     = Oats::VERSION
  s.authors     = ["Levent Atasoy"]
  s.email       = ["levent.atasoy@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{A flexible automated system integration regression test framework.}
  s.description = %q{A flexible automated system integration regression test framework.}

  s.rubyforge_project = "oats"
  if RUBY_PLATFORM !~  /(mswin|mingw)/ # Does not like git ls-files
    s.files         = File.directory?('.git') ? `git ls-files`.split("\n") : []
    s.test_files    = File.directory?('.git') ? `git ls-files -- {test,spec,features}/*`.split("\n") : []
  end
  #  s.test_files = ["test/test_cgi_wrapper.rb" ]
  s.executables   = %w{oats}
  s.require_paths = ["lib"]

  #   s.extra_rdoc_files = ["CHANGELOG", "COPYING", "lib/oats/oats.rb", "LICENSE", "README"]
  #  s.has_rdoc = true
  #  s.homepage = %q{http://oats.org}
  #  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Oats", "--main", "README"
  s.date = %q{2012-05-22}
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7")

  s.add_dependency 'log4r'
  s.add_dependency 'net-http-persistent' unless RUBY_VERSION =~ /^1.9/ # Speed up 1.8 connections

  if RUBY_PLATFORM =~ /(mswin|mingw)/ # Assume won't use the agent
    s.add_dependency 'win32-process'
  else
    s.add_dependency 'json'
    s.add_dependency 'em-http-request'
    if RUBY_PLATFORM =~ /linux/ # Seems to be needed by Ubuntu
      s.add_dependency 'execjs'
      s.add_dependency 'therubyracer'
    end
  end
end
