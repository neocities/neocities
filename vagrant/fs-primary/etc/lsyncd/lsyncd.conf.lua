-- Inotify listener max needs to be turned up. Assume 2KB per directory watched.
-- The number of mirrored directories is the relevant variable because a Linux watch is created for each directory.
-- It may make more sense to use a SITENAME_FILENAME strategy here instead of directory partitioning.
-- The below example is 10 gigabytes / 2 = number of watches for 10GB, which is 5 million directories.
-- echo 5000000 > /proc/sys/fs/inotify/max_user_watches
-- For /etc/sysctl.conf: fs.inotify.max_user_watches=5000000
-- Make sure maxProcesses is below ssh's MaxSessions (default is 10)
settings {
  logfile = "/var/log/lsyncd.log",
  statusFile = "/var/log/lsyncd-status.log",
  maxProcesses = 8
}
sync {
  default.rsyncssh,
  delete=true,
  source="/home/*ACCOUNT*/testone",
  host="*HOST*",
  targetdir="/home/*ACCOUNT*/testone",
  rsync = {
    compress = true,
    archive = true,
    perms = true,
    owner = true
  },
  delay=0
}
