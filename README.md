# Just a logs parser with grep and perl

A tool to parse generic logs (originally Fuel for OpenStack logs)
collected via diagnostic tools, or stored live on servers, or stored at logs
aggregation servers' `/var/log/node-{foo,bar,baz}` directories, or the
like. Logged events are normally processed as the following:

 * filtered (`grep -HEIr`) from sources living in the $pwd, like directories
   representing nodes sending logs remotely, or just /var/log/ subdirs;
 * then magic mutators applied, like decoding timestamps for autdit denials,
   or transforming python-ish timestamps into rfc3339 looking-like format;
 * then sorted by its timestamps (rfc3164 or rfc3339-ish),
 * finally, a from/to ranges applied, if requested.

Use `-h` key to get some help.

## Examples for generic logs parsing exercises

Get all MySQL related events and sort by the timestamp, limit results
collected from 2015-11-11T09:38:36 to 2015-11-11T09:58:25 (rfc3339):
```
$ ./fuel-log-parse.sh -s "MySQL|sql" -f 2015-11-11T09:38:36 \
    -t 2015-11-11T09:58:25 | less
```

Get all known-to-be-faily events (hereafter, just 'errors') from all sources,
but not from foo and bar:

```
$ ./fuel-log-parsh.sh -x "foo-component|bar-component"
```

Search for errors with a given source-matching pattern (applied for source
directories' names). Looks for events logged only with rfc3164 timestamps.
Also, translates 'avc: denied' audit events with a mutator (gives no source tags,
like node names!):

```
$ ./fuel-log-parsh.sh -n "node[0-9]+" -rfc3164
```

Parse for errors from all sources and for all ansible PLAY/TASK events. Mutate
a python-ish timestamps into something looking more rfc3339-ish (a mutator).
Hide tracebacks:

```
$ ./fuel-log-parse.sh -n ".*"
```

## Examples for Tripleo CI (OpenStack infra) logs

There is a
[getthelogs](https://git.openstack.org/cgit/openstack-infra/tripleo-ci/tree/scripts/getthelogs)
tool for downloading Tripleo CI jobs' logs.
It recursively fetches the most important logfiles, like those from the
`undercloud/home/jenkins`, `/var/log`, `/subnode-*/var/log`,
`overcloud*/var/log` locations, and the `console.html` file (zuul v2), and it
works with zuul v3 also.

Example that shows only errors, rfc3164 formatted, plus avc (audit) events
decoded with a magic mutator:
```
$ getthelogs http://logs.openstack.org/<cryptic-stuff>/<gate-name>/<job-id-hash>
$ fuel-log-parse -n ".*" -rfc3164
```

Note that avc events have *no source info provided*, but there is a log file
path given at very least. Use `-rfc3164` to see avc events decoded, this
mutator doesn't work with default `-rfc3339`.

Another example hides names of executed ansible tasks, finds errors for all of
the mutatable python-ish/rfc3339 formatted events. Another magic mutator adds
extracted rfc3339 timestamps, if any available from events originally logged
with rfc3164 format (just checks if there is `time="<stamp>"` in messages).
It also drops *ugly*, **long**, multiline messages logged by ansible, heat,
mistral and the like JSON-lovers:
```
$ fuel-log-parse -x "TASK|PLAY|INFO|\\\"" -n ".*"
```
Note, it can't sort rfc3164 (Mar 22 13:34:08) time among with py/rfc3339 format.
Use another command to inspect with `-rfc3164`.

Also note that those ugly multiline JSON events might be an only source for
tricky errors hiding in, sitting in the middle of a kilometer-length message.
Just keep that in mind, if filtering them out. You may want to come back to
inspect them later as well.

# OpenStack Elastic-Recheck verified/known patterns

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

## Examples of ES queries

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
