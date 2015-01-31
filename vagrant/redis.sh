apt-get install -y redis-server 

#sed -i 's|[#]*appendfsync everysec|appendfsync always|g' /etc/redis/redis.conf
sed -i 's|[#]*appendonly no|appendonly yes|g' /etc/redis/redis.conf

service redis-server restart