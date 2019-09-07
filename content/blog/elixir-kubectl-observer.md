---
title: "Using Erlang's Observer in Kubernetes for an Elixir Release"
date: 2019-09-02T15:25:13-07:00
description: "A guide to using Erlang's observer in Kubernetes for an Elixir Release."
tags: ["kubernetes", "elixir", "phoenix"]
draft: false
---

Erlang's observer is awesome. There are a lot of anecdotes on the usefulness of it for debugging production systems, and one of my favorites is how the [Phoenix team used it to find a process that was filling up it's mailbox](https://phoenixframework.org/blog/the-road-to-2-million-websocket-connections).

Most of the guides out there are for using it with [vanilla ssh](http://blog.plataformatec.com.br/2016/05/tracing-and-observing-your-remote-node/).

We'll work through getting a local Observer talking with a Kubernetes pod in production.

## Pre-requisites

* A Phoenix App using Elixir 1.9 Releases (At some point, I plan to write a complete getting started with Kubernetes and Phoenix from scratch guide)
* That is deployed in Kubernetes
* All kubectl commands should be run in your application's namespace

## Create a Secret Cookie

A shared secret (or cookie, as Erlang calls it) is required for connecting to Erlang nodes.

```shell
mix phx.gen.secret | base64 | tr -d "\n" > release_cookie
kubectl create secret generic release --from-file=release_cookie
rm release_cookie
```

Note: the `base64` part of the above command is because the [release docs state you should restrict the characters to that encoding](https://hexdocs.pm/mix/Mix.Tasks.Release.html). 

## Use that Cookie in your Kubernetes file

```yaml
          env:
            - name: RELEASE_COOKIE
              valueFrom:
                secretKeyRef:
                  name: release
                  key: release_cookie
```

## Update your release files

Add or uncomment the following to your `rel/env.sh.eex`

```bash
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=<%= @release.name %>@127.0.0.1

case $RELEASE_COMMAND in
  start*|daemon*)
    ELIXIR_ERL_OPTIONS="-kernel inet_dist_listen_min $BEAM_PORT inet_dist_listen_max $BEAM_PORT"
    export ELIXIR_ERL_OPTIONS
    ;;
  *)
    ;;
esac
```

This does two important things:

1. It exports the RELEASE_NODE variable. Without this, the node will not let you connect to it from outside of the pod. I received `Could not contact remote node budgetsh@127.0.0.1, reason: :nodedown. Aborting...` when I tried.
2. It gives you a known port to forward.

Next, add that environment variable to your K8S file:

```yaml
          env:
            - name: BEAM_PORT
              value: 9001 # this is arbitrary
            - name: RELEASE_COOKIE
```

## Deploy the New Code

Ensure your code and kubernetes changes have been deployed.o

## Use Observer

First, you are going to need to forward some ports. Specifically, BEAM_PORT, and 4369. 4369 is for epmd, [the erlang port mapper daemon](http://erlang.org/doc/man/epmd.html).

```shell
 kubectl port-forward POD_NAME 9001 4369
```

Next, spin up an IEX session with the correct cookie:

```shell
iex --name $(whoami)@127.0.0.1 --cookie $(kubectl get secret release -o "go-template={{index .data \"release_cookie\"}}" | base64 -D)
```

From there, run `:observer.start()` in the iex session, and select your pod's erlang node from the menu bar. 

Note: I tried getting this working in one command, ie:

```shell
iex --name dan@127.0.0.1 --cookie SECRET_COOKIE --remsh budgetsh@127.0.0.1
```

but, when I got into an IEX session, I received: `function :observer.start/0 is undefined`. This is because my Phoenix application does not specify :observer, and :wx as applications, and it should not. Production applications do not need this bloat; `runtime-tools` is likely enough.

## Conclusion

* At some point, I'd like  to get this working with proper Erlang node clustering.
* It's probably easy to orchestrate all this better in a one line command. Especially since Kubernetes has an API that provides port forwarding.
  * Right now, I just have an alias for the IEX command:

  ```bash
  alias reliex='iex --name $(whoami)@127.0.0.1 --cookie $(kubectl get secret release -o "go-template={{index .data \"release_cookie\"}}" | base64 -D)'
  ```

* Getting an application deployed and an observer open is much easier on [gigalixir](https://gigalixir.com).
* Please leave a comment below if these did not work for your, or if there's a glaring typo somewhere. (or open an issue [here](https://github.com/djquan/quan.io)
* Feel free to take a look at my [WIP toy app where I'm testing all this stuff out](https://github.com/djquan/budget.sh)
