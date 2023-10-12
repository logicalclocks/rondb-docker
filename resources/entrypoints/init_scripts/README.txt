Add SQL scripts here that will be run at startup of the MySQLd container.
Be sure to make these scripts idempotent, since they could be run again
if the container is restarted. Do so by using `IF NOT EXISTS` to the SQL
commands.
