# fuel-log-parse

A tool to parse fuel logs collected via diagnostic snapshots
or live, being run at the Fuel master node's
`/var/log/docker-logs` directory. Events normally are collected
across all nodes and sorted by its timestamps.

Use `-h` key to get some help.

Note, that the key `-2` should not be used with other keys as
it is a separate parser for atop log entries collected with
the `atop -PPRG -r <...>` command

*Examples:*

Note, it should be run from the `<...>/docker-logs` directory.

Get all MySQL related events across existing OpenStack nodes
deployed by Fuel and sort the by a timestamp, and limit results
collected from 2015-11-11T09:38:36 to 2015-11-11T09:58:25.

```
./fuel-log-parse.sh "MySQL|sql" -f 2015-11-11T09:38:36 \
    -t 2015-11-11T09:58:25 | less
```

Get key deployment orchestration events

```
./fuel-log-parse.sh -d -1
```

Get all faily-like events and tracebacks from nodes AND
Fuel components like Nailgun, keystone, orchestration astute,
mcollective, messaging, fuel agent etc.

```
./fuel-log-parse.sh -1
```

Get all faily-like events from nodes but not from the
foo and bar components

```
./fuel-log-parsh.sh -x "foo-component|bar-component"
```
