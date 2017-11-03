# Just a logs parser with grep and perl

A tool to parse (for events) generic logs (originally Fuel for OpenStack logs)
collected via diagnostic tools, or stored live on servers, or stored at logs
aggregation servers' `/var/log/node-{foo,bar,baz}` directories, or the
like. Logged events are normally processed as the following:

 * filtered (grep -HEir) from '.' sources, like directories representing nodes;
 * then magic mutators applied, like decoding avc timestamps into rfc3164, or
   transforming python timestamps into rfc3339 looking-like format;
 * then sorted by its timestamps (rfc3164 or rfc3339-ish),
 * finally, a from/to ranges applied, if requested.

Use `-h` key to get some help.

## Odd modes for odd things

There is also a simple tool to query elasticsearch indexes for events.

Note, that the key `-2` should not be used with other keys as
it is a separate parser for atop log entries collected with
the `atop -PPRG -r <...>` command.

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
nodes naming pattern and expecting RFC3164 timestamps. Also,
translate "bad" avc audit events' epoch into timestamps.

```
$ ./fuel-log-parsh.sh -n "node[0-9]+" -rfc3164
```

Parse also ansible logs for main events and expecting a generic
Python-like timestamps.

```
$ ./fuel-log-parse.sh -n "node[0-9]+"
```

## Examples for Tripleo CI (OpenStack infra) logs

There is a `getthelogs` tool for downloading Tripleo CI jobs' logs.
It recursively fetches the most important logfiles, like those from the
`undercloud/home/jenkins`, `/var/log`, `/subnode-*/var/log`,
  `overcloud*/var/log` locations, and the `console.html` file.

Example:
```
$ getthelogs http://logs.openstack.org/43/448543/3/check/gate-tripleo-ci-centos-7-nonha-multinode-oooq/9ece507
$
# Show only errors on subnodes (rfc3164)
$ fuel-log-parse -n ".*subnode.*" -rfc3164
$
# Show names of executed ansible tasks and generic errors in the py/rfc3339/3164 formatted logs
# Also drop unrelated CI infra noise and ansible "test -f" messages
$ export X="test|session|secure"
$ fuel-log-parse -x "$X" -n ".*"
$ fuel-log-parse -x "$X" -n ".*" -rfc3164
```
Note, it can't sort rfc3164 (Mar 22 13:34:08) time among with py/rfc3339 format. Yet.
A mutator translating journald rfc3164 time stamps to the msg-contained rfc3339
TBD.

# OpenStack Elastic-Recheck verified patterns

There is a list of known/proved to be faily elastic-recheck query
[patterns](https://git.openstack.org/cgit/openstack-infra/elastic-recheck/tree/queries).
A pattern  is considered faily, when the `elastic-recheck-query` check shows
`build_status` > 80% FAILURE for it. F.e. the 'Permission denied' pattern is a highly
faily (87% FAILURE).

Instead, a non faily pattern would show more than a 50% SUCCESS rate or ~50/50. Like a
notorious "MessagingTimeout: Timed out waiting for a reply" message. Those non faily
patterns are collected under the script's `echeck_verified_ignore` var. And can be
runtime filtered out from search results with the command line argument `-echeck`.
Note, those will be *added* to the default list of dropped patterns.

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
