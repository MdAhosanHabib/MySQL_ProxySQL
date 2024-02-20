################################ Start Stop MySQL Master/Slave ################################
On the Slave:
-------------
mysql -u root -p

STOP SLAVE SQL_THREAD;
STOP SLAVE IO_THREAD;
START SLAVE SQL_THREAD;
START SLAVE IO_THREAD;

STOP SLAVE;
START SLAVE;
SHOW SLAVE STATUS\G;

-- to stop write
SET GLOBAL read_only = 1;
SHOW VARIABLES LIKE 'read_only';

or

# vi /etc/my.cnf
[mysqld]
read_only = 1

systemctl restart mysqld

-- to start write
SET GLOBAL read_only = 0;
SHOW VARIABLES LIKE 'read_only';

On the Master (Optional):
-------------------------
mysql -u root -p

STOP BINLOG;
START BINLOG;

STOP MASTER;
START MASTER;

SHOW MASTER STATUS\G;

################################ ProxySQL LB install ################################
# Install ProxySQL:
[root@master1 proxysql]# chown -R proxysql:proxysql /var/lib/proxysql/
[root@master1 datafile]# dnf install -y https://repo.proxysql.com/ProxySQL/proxysql-2.5.x/almalinux/9/proxysql-2.5.5-1-almalinux9.x86_64.rpm

# Start ProxySQL Service:
systemctl start proxysql

# Enable ProxySQL on Boot:
systemctl enable proxysql

Configure ProxySQL:
[root@master1 datafile]# dnf install mysql
Access ProxySQL Admin:
mysql -u admin -padmin -h 127.0.0.1 -P 6032 --prompt='ProxySQLAdmin> '

################################ Configure ProxySQL ################################
ProxySQL Admin> SELECT * FROM mysql_servers;
ProxySQL Admin> SELECT * from mysql_replication_hostgroups;
ProxySQL Admin> SELECT * from mysql_query_rules;

Configure MySQL Servers:
ProxySQL Admin> INSERT INTO mysql_servers(hostgroup_id,hostname,port) VALUES (1,'192.168.141.129',3306);
ProxySQL Admin> INSERT INTO mysql_servers(hostgroup_id,hostname,port) VALUES (2,'192.168.141.130',3306);
ProxySQL Admin> INSERT INTO mysql_servers(hostgroup_id,hostname,port) VALUES (2,'192.168.141.131',3306);
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
select * from mysql_servers;

Configure Hostgroups:
ProxySQL Admin> SHOW CREATE TABLE mysql_replication_hostgroups\G
ProxySQL Admin> INSERT INTO mysql_replication_hostgroups (writer_hostgroup,reader_hostgroup,comment) VALUES (1,2,'cluster1');
ProxySQL Admin> LOAD MYSQL SERVERS TO RUNTIME;
ProxySQL Admin> SELECT * FROM mysql_servers;

ProxySQL Admin> SELECT * FROM monitor.mysql_server_read_only_log ORDER BY time_start_us DESC LIMIT 3;

ProxySQL Admin> SELECT * FROM mysql_servers;
ProxySQL Admin> SAVE MYSQL SERVERS TO DISK;
ProxySQL Admin> SAVE MYSQL VARIABLES TO DISK;

INSERT INTO mysql_query_rules (active, match_digest, destination_hostgroup, apply) VALUES (1, '^SELECT .*', 2, 1);
INSERT INTO mysql_query_rules (active, match_digest, destination_hostgroup, apply) VALUES (1, '.*', 1, 1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
select * from mysql_query_rules;

These rules direct SELECT queries to hostgroup 2 (slaves) and other queries to hostgroup 1 (master).

Create at master DB:
mysql> CREATE USER 'monitor'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'monitor#12M';
mysql> GRANT USAGE, REPLICATION CLIENT ON *.* TO 'monitor'@'%';
mysql> FLUSH PRIVILEGES;

CREATE USER 'test1'@'master1.k8s' IDENTIFIED WITH 'mysql_native_password' BY 'test#12M';
GRANT ALL PRIVILEGES ON test1.* TO 'test1'@'master1.k8s';
FLUSH PRIVILEGES;

User set in ProxySQL:
ProxySQL Admin> UPDATE global_variables SET variable_value='monitor' WHERE variable_name='mysql-monitor_username';
ProxySQL Admin> UPDATE global_variables SET variable_value='monitor#12M' WHERE variable_name='mysql-monitor_password';

ProxySQL Admin> UPDATE global_variables SET variable_value='2000' WHERE variable_name IN ('mysql-monitor_connect_interval','mysql-monitor_ping_interval','mysql-monitor_read_only_interval');
ProxySQL Admin> SELECT * FROM global_variables WHERE variable_name LIKE 'mysql-monitor_%';

ProxySQL Admin> LOAD MYSQL VARIABLES TO RUNTIME;
ProxySQL Admin> SAVE MYSQL VARIABLES TO DISK;

ProxySQL Admin> SHOW TABLES FROM monitor;
ProxySQL Admin> SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 3;
ProxySQL Admin> SELECT * FROM monitor.mysql_server_ping_log ORDER BY time_start_us DESC LIMIT 3;

ProxySQL Admin> SELECT * FROM mysql_users;
INSERT INTO mysql_users(username, password, default_hostgroup) VALUES ('test1', 'test#12M', 1);
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
select * from mysql_users;

ProxySQL Admin> update mysql_servers set weight=100 where hostname = '192.168.141.130';
ProxySQL Admin> update mysql_servers set weight=100 where hostname = '192.168.141.131';
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
select * from mysql_servers;

ProxySQLAdmin> SELECT hostgroup, srv_host, status, Queries FROM stats.stats_mysql_connection_pool;

################################ Test ProxySQL ################################
mysql -u test1 -ptest#12M -h 127.0.0.1 -P 6033 -e"SELECT @@port"
mysql -u test1 -ptest#12M -h 127.0.0.1 -P 6033 -e "select @@hostname"

use test1;
SELECT * FROM test1.test1;

INSERT INTO test1 (name, event_date) VALUES ('Ahosan', '2022-02-01');
SELECT * FROM test1.test1;
DELETE FROM test1.test1 WHERE id =8;
COMMIT;

################################ Web portal enable ProxySQL ################################
To enable it it is enough to configure admin-web_enabled=true:
ProxySQLAdmin> SET admin-web_enabled='true';
ProxySQLAdmin> LOAD ADMIN VARIABLES TO RUNTIME;

[root@master1 datafile]# telnet 192.168.141.128 6080

https://192.168.141.128:6080
User:stats Pass:stats

Similarly, to disable it:
ProxySQLAdmin> SET admin-web_enabled='false';
ProxySQLAdmin> LOAD ADMIN VARIABLES TO RUNTIME;

