$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "monster_provisions/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "monster-provisions"
  s.version     = MonsterProvisions::VERSION
  s.authors     = ["Monsterbox Productions"]
  s.email       = ["andrew@monsterboxpro.com"]
  s.homepage    = "http://monsterboxpro.com"
  s.summary     = 'Provisioning'
  s.description = 'Provisioning'
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 4.1.5"

  s.add_development_dependency "sqlite3"
end
