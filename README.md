# CPEE Instantiation

To install the instatiation service go to the commandline

```bash
 gem install cpee-instantiation
 cpee-instantiation instantiation
 cd instantiation
 ./instantiation start
``` 

 The service is running under port 9296. If this port has to be changed (or the
host, or local-only access, ...), create a file instatiation.conf and add one
or many of the following yaml keys:

```yaml
 :port: 9250
 :host: cpee.org
 :bind: 127.0.0.1
```

To use the service try one of the following:

```bash
 curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "behavior=wait_running&url=http%3A%2F%2Flink%2Fto%2Ftestset.xml" http://localhost:9296/url
 curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "behavior=fork_running&url=http%3A%2F%2Flink%2Fto%2Ftestset.xml&init=%7B%20%22a%22%3A%2037%2C%20%22b%22%3A%20%22test%22%20%7D" http://localhost:9296/url
 curl -X POST -F "behavior=wait_running" -F "xml=@testset.xml" http://localhost:9296/xml
``` 

The behavior can be either: the process parent process is waiting (wait_) or is
running in parallel (fork_), the subprocesss is either immediately starting
(_running), or waiting for manual start (_ready).
