== Welcome to OATS

The goal of the Automated Testing Project is to implement the tools,
environment, and processes that will enable a QA team to create system
integration regression test cases which can be executed by QA, Development
teams, or build scripts in a simple or automated fashion.


== License

OATS is copyright 2012 Levent Atasoy and contributors. It is licensed under the
Ruby license and the GPL. See the included LICENSE file in doc folder for
details.


== OATS Installation

  - Install
    - Ruby 1.8.7
    - Ruby Bundler
    - gem install oats

  - On Windows_NT, some operations need handle.exe and psexec.exe to be in the
    PATH.  These are found in PsTools Suite from
    http://technet.microsoft.com/en-us/sysinternals

  - Recommended to also install Netbeans (or another IDE of your choice)
 

== Configuring OATS

   OATS_HOME below refers to the oats gem installation folder
  - Set the HOME variable C:\myDirectory
  - Set USER PATH for ..\ruby\bin; C:\myDirectory\oats\bin
    At this point you should be able to type 'oats' in commandline and see the
    execution of a sample test.
  - See OATS_HOME/doc/oats_ini.yml for customizable properties.
  - Copy sample OATS_HOME/oats_tests folder to <yourTestFolder> and start adding your
    own tests.
  - Copy sample OATS_HOME/doc/oats-user.yml to HOME, and set 'dir_tests' to
    your <yourTestFolder>


== Using OATS with NetBeans

  - Download NetBeans from http://netbeans.org/downloads
  * NetBeans 7.1.2 or higher is not recommended, as the Ruby debugger seems
    to have issues on it as of 05/04/2012
  * If you install NetBeans 7/0-7.1.1, you'll need to install Ruby Plug-ins manually
    For using only Ruby with these versions download smallest footprint of
    NetBeans, e.g. NetBeans C/C++).
    To install NBMs:
      1. Download
      http://jruby.org.s3.amazonaws.com/downloads/community-ruby/community-ruby_7_1_preview1.zip
      2. Select Tools->Plugins from menu
      3. Select Downloaded tab
      4. Press Add Plugins...
      5. Navigate to where you unzipped the nbms files
      6. Select all files which end in .nbms (you can do this all in one selection
         but if you include any non-nbms file it greys out the open button)
      7. Accept and install

  - Create a new Ruby project in NetBeans for OATS Framework
  * Select "Ruby Application with Existing Sources"
  * Use project name 'oats'.
  * Add Folder 'lib' under the cloned 'oats' folder into 'Existing Sources'
  * Add Folder 'oats_tests' under the cloned 'oats' folder into 'Test Folders'
  * Add Folder <yourTestFolder> into 'Test Folders'.
  * Select oats Project Properties -> Run
    - Ensure your Ruby Platform is shown on the drop down list.
    - For Main Script, select 'oats_main.rb'


== Additional Ruby Installation Guidance For Windows

  http://rubyinstaller.org/downloads/
  https://github.com/oneclick/rubyinstaller/wiki/development-kit
  1. Install ruby 1.8.7
    - 1.9.x doesn't build ruby-debug-ide19
    - gem install --pre ruby-debug-base19x for base only
  2. Unzip the rubydev kit and copy all bin files into ..\ruby\bin
  3. copy the devkit directory into ...\ruby
  4. Left double-click the self-extracting executable (SFX) downloaded and
     choose a directory to install the DevKit artifacts into.
     For example, C:\DevKit
  5. cd <DEVKIT_INSTALL_DIR>
     example: cd Devkit
  6. ruby dk.rb init to generate the config.yml
  7. check the config file for correct version of ruby.
  8. finally, ruby dk.rb install to DevKit enhance your installed Rubies.


==  LibCurl Installation (Needed only if your tests would use LibCurl)

  http://beginrescue.blogspot.com/2010/07/installing-curb-with-ruby-191-in.html
  http://www.gknw.de/mirror/curl/win32/old_releases/

  1. gem install oauth (from command line)
  2. download libcurl  make sure to get the one for mingw32 and that you
     get libcurl and not plain-old curl.
     or  get libcurl from \\opfiler\qa\oatsSetup (curl-7.21.1-devel-mingw32)
  3. copy or extract files in C drive
  4. copy bin files to ..\ruby\bin
  5. gem install curb -- --with-curl-lib=C:\curl-7.21.1-devel-mingw32\bin \
     	 --with-curl-include=C:\curl-7.21.1-devel-mingw32\include
  6. Add  '...\curl-7.21.1-devel-mingw32\bin' to USER PATH



== Ruby 1.9.X IDE Debug setup
To use IDE debugger with 1.9.X, you will need to install 'ruby-debug19' instead
of 'ruby-debug' gem and follow the instructions found in:
  http://noteslog.com/post/netbeans-6-9-1-ruby-1-9-2-rails-3-0-0-debugging
It instructs you to apply the following patch to:
(Ruby folder)/lib/ruby/gems/1.9.1/gems/ruby-debug-ide19-0.4.12/bin/rdebug-ide.rb
 #  noteslog.com, 2010-09-17 -> !!!
 # 78 Debugger::PROG_SCRIPT = ARGV.shift
 script = ARGV.shift
 Debugger::PROG_SCRIPT = (script =~ /script([\\\/])rails/ ? Dir.pwd + $1 : '') + script


== Selenium IDE

Though not required for OATS execution you need to download and install the
latest Selenium IDE plug- in from http://seleniumhq.org/download/, or from the
list of Firefox plugins in order to create and run tests via the Selenium IDE on
Firefox.  Read the IDE documentation at http://seleniumhq.org to learn about IDE
usage.
To use Chrome with Webdriver, download and put the chromedriver applicable to
your machine in the PATH for OATS.


== MySQL Client

If your tests interact with MySQL, then you need to install a MySQL client which
is the default DB interface provided by OATS. Many of the OATS tests require
interaction with the various RL applicaton MySQL databases.  In order to
interact with the MySQL databases on various environments, OATS expects to find
the MySQL client in the PATH. To verify this, open a Windows CMD window and type
'mysql \--help'. If you see an error message instead of MySQL help, make sure
MySQL is installed on your system and that the bin directory of MySQL is
included in the PATH.


== Putty and Pageant (For Windows-OCC and Windows-Agent Installations)

Installation of PuTTY, Pageant, Puttygen, and Plink are necessary if your tests
require access to systems via ssh. For Linux systems the default methods used by
OATS to interrogate logs or execute scripts on remote is via Plink, using ssh.
Pageant is also useful to install if you are using tortoise to access SVN setup
with SSH.
  
  1. Download and install PuTTY, Pageant, Puttygen, and Plink from
     http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html. These are
     standalone executables, so you can install them wherever you'd like.
  2. Once the PUTTY is installed, append <putty-installation-dir>/PuTTY to
     the user environment variable PATH (create it if it does not exist.)
  3. Use PuTTYgen to Generate Public and Private Keys, and incorporate them
     in your appropriate authorized_keys files and .ssh folders

