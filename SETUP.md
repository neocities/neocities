# Neocities Local Development Setup

## On Windows (host machine)

1. Install Ruby
   ```
   winget install RubyInstallerTeam.Ruby.4.0
   ```

2. Add Ruby to your PATH (run in PowerShell)
   ```powershell
   $rubyPath = "C:\Ruby40-x64\bin"
   $oldPath = [Environment]::GetEnvironmentVariable("Path", "User")
   if ($oldPath -notlike "*$rubyPath*") {
       [Environment]::SetEnvironmentVariable("Path", $oldPath + ";$rubyPath", "User")
   }
   ```
   Then restart your terminal for the change to take effect.

3. Clone the repository
   ```
   git clone https://github.com/bald-cap/neocities.git
   cd neocities
   ```

3. Fix line endings on Vagrant scripts
   ```
   dos2unix vagrant/common.sh vagrant/database.sh vagrant/development.sh vagrant/fs-primary.sh vagrant/redis.sh vagrant/ruby.sh vagrant/webapp.sh
   ```

4. Install Vagrant
   ```
   winget install --id Hashicorp.Vagrant
   ```

5. Copy config file
   ```
   cp config.yml.template config.yml
   ```

6. Start and provision the VM
   ```
   vagrant up --provision
   ```

7. SSH into the VM
   ```
   vagrant ssh
   ```

## Inside the VM

8. Add the rackup gem
   ```
   sudo bundle add rackup
   ```

9. Install gems
   ```
   sudo bundle install
   ```

10. Start the server
    ```
    bundle exec rackup -o 0.0.0.0
    ```

The site will be available at http://127.0.0.1:9292
