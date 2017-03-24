# fuel-log-parse

A tool to parse fuel or generic logs collected via diagnostic
tools or live, being run at the central log server node's
`/var/log/foo` directory. Events normally are collected
across all nodes/pods and sorted by its timestamps. There is
also a simple tool to query elasticsearch indexes for events.

Use `-h` key to get some help.

Note, that the key `-2` should not be used with other keys as
it is a separate parser for atop log entries collected with
the `atop -PPRG -r <...>` command

## Examples

Get all MySQL related events across existing OpenStack nodes
deployed by Fuel and sort the by a timestamp, and limit results
collected from 2015-11-11T09:38:36 to 2015-11-11T09:58:25.

```
$ ./fuel-log-parse.sh "MySQL|sql" -f 2015-11-11T09:38:36 \
    -t 2015-11-11T09:58:25 | less
```

Get key deployment orchestration events (Fuel only)

```
$ ./fuel-log-parse.sh -d -1
```

Get all faily-like events and tracebacks from nodes AND
Fuel components like Nailgun, keystone, orchestration astute,
mcollective, messaging, fuel agent etc.

```
$ ./fuel-log-parse.sh -1
```

Get all faily-like events from nodes but not from the
foo and bar components

```
$ ./fuel-log-parsh.sh -x "foo-component|bar-component"
```

Collect errors from logs collected by generic ansible
playbooks based on the fetch module. Search using a given
nodes naming pattern and expecting RFC3164 timestamps.

```
$ ./fuel-log-parsh.sh -n "node[0-9]+" -rfc3164
```

Parse ansible logs for main events and expecting a generic
Python-like timestamps.

```
$ ./fuel-log-parse.sh -n "node[0-9]+" -py
```

## Examples for Tripleo CI (OpenStack infra) logs

There is a [getthelogs](https://github.com/openstack-infra/tripleo-ci/blob/master/scripts/getthelogs)
tool for OOO CI. It can be used to fetch some logs.
Note, nested directories won't be auto downloaded.
```
$ export ASK=no
$ export ENTER=no
$
# Get generic logfiles from the subnode-1
$ getthelogs http://logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507/logs/subnode-1/var/log
$
# Get jenkins logs from tasks ran at the subnode-1
$ getthelogs http://logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507/logs/subnode-1/home/jenkins/
$
# Get what we have from the node-2
$ getthelogs http://logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507/logs/subnode-2
$
# Get undercloud Heat logs
$ getthelogs http://logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507/logs/undercloud/var/log/heat/
$
# Get all logs from the CI job done by OOOQ (TripleO QuickStart)
$ getthelogs http://logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507/logs/undercloud/home/jenkins/
$
$ cd ~/tmp/ci-logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507/
$
# Show only errors on subnodes (rfc3164)
$ fuel-log-parse -n ".*subnode.*" -rfc3164
$
# Show names of executed ansible tasks and generic errors in the py/rfc3339 formatted logs
$ fuel-log-parse -n ".*"
$
# Run parser for *all* events with py/rfc3339 timestamps, with or w/o node names given
$ ./fuel-log-parse.sh -n ".*" -s ".*"
```
Note, it can't sort rfc3164 (Mar 22 13:34:08) time among with py/rfc3339 format. Yet.

# ES searcher script for OpenStack

Additionally, there is a simple ES searcher script. It expects log
messages indexed by ES in a specific way and have specific fields, like
the payload or request id. See [ES official docs](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-uri-request.html).
See also [Fuel CCP](http://fuel-ccp.readthedocs.io/en/latest/).

It requires perl, curl, jq, kubectl (optional).

## Examples

```
esip=$(kubectl get pods --namespace foo --selector=app=elasticsearch \
  --output=jsonpath={.items..status.podIP})
curl -s "$esip:9200/_cat/indices"
```

The command gives you a list of ES indices queried from an elasticsearch
app running as a Kubernetes pod. Next, you can issue a search request against
a given index, or all of them (by default):

```
ESIP=$esip ESIND=log-2016.09.21 SIZE=100 k8s_es_search.sh "*:*"
ESIP=$esip k8s_es_search.sh "/.*/"
```

This matches all events and limits the result output to a 100 log records, ordered
by a ascending timestamps.

Note that a search query will be executed for logged messages' payload and
severity level and other types of indexed fields, like OpenStack request ID:

```
ESIP=$esip k8s_es_search.sh "*WARN*"
```

TODO: integrate ES searcher with the common fuel log parse tool to
match and view all types of events as a single output.

The default search pattern is a regex ``/error|alert|trace.*|crit.*|fatal/``:

```
ESIP=$esip SIZE=5000 k8s_es_search.sh
```

