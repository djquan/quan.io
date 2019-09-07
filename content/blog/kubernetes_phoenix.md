---
title: "Deploying Phoenix to Kubernetes from Scratch"
date: 2019-09-06T18:43:51-07:00
draft: false
description: "A guide to Deploying Phoenix to Kubernetes completely from scratch."
tags: ["kubernetes", "elixir", "phoenix"]
---

## Introduction

Kubernetes is such an exciting technology, but it can be overwhelming when starting. There are many reasons to use Kubernetes, and likely an equal number of valid reasons to use something different. I don't have anything interesting or new to add to that debate though. I use Kubernetes [at work](https://braintreepayments.com/careers) and for personal projects, and I love the options it gives me for deploying applications. There's an initial burden when getting the cluster set up and learning the basics, but deploying applications is easy and quick after.

I highly recommend [Gigalixir](https://gigalixir.com) if Kubernetes does not excite you, and all you want is a simple and reliable way to deploy a Phoenix application.

This post is meant to be a complete guide for deploying a brand new Phoenix application to a brand new Kubernetes cluster. There are no pre-requisites to this, but I will call out places where you can substitute your existing solutions. I am not a Kubernetes or Elixir/Phoenix expert, so there are likely better ways of doing things. If you see such things, please leave a comment or [open an issue](https://github.com/djquan/quan.io/issues/new).

The code I used in this guide lives [in github](https://github.com/djquan/kubernetes-phoenix), and can be used as a reference.

## A Note About Costs

You should be able to complete this tutorial for free: Digital Ocean and Google Cloud (and AWS, and Azure, and more) provide trial credits which should get you up and running. [This is my digital ocean referral link](https://m.do.co/c/bac4b0edfb0a) that should get you $50 in credits, which should be plenty for this tutorial. I believe Google Cloud also offers $300 for new accounts. This tutorial, however, will only be using Digital Ocean products. There are some ways to cut costs when running a Kubernetes cluster, which I will also try to call out.

There are completely free ways of playing around with Kubernetes locally, but it's been my experience that it's easier to learn on real Kubernetes clusters. If you have more than one old spare computer, building a Kubernetes cluster from those is enriching and fun, but using a managed Kubernetes solution lets you focus on deploying applications.

## The Kubernetes Cluster

Digital Ocean provides a fantastic Kubernetes product. It lacks some of Google's bells and whistles, but it's cheaper and works really well. As mentioned above, you can use [my referral link](https://m.do.co/c/bac4b0edfb0a) to get free credits. If you have a Kubernetes cluster already, you can skip to the next section.

Once you create a new account, navigate to the [Kubernetes cluster creation page](https://cloud.digitalocean.com/kubernetes/clusters/new). Create a new cluster

- using the latest Kubernetes version
- in the region closest to you
- with 3 $10/month nodes. Digital Ocean does let you create a two node cluster, so this is an area to save money if high availability is not your primary concern.

I've named my cluster `test-phoenix-cluster`.

It'll take a few minutes to start up your new Kubernetes cluster, so take this time to follow the [instructions on connecting to a Digital Ocean cluster](https://www.digitalocean.com/docs/kubernetes/how-to/connect-to-cluster/). This requires setting up [Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) and [doctl](https://github.com/digitalocean/doctl#installing-doctl). Setting up [Kubectx and Kubens](https://github.com/ahmetb/kubectx) is also recommended (but not strictly necessary).

After your cluster is ready, run: `doctl kubernetes cluster kubeconfig save test-phoenix-cluster` to set up your config and authentication.

When you are finished, you should be able to run the following and get similar results:

```bash
$ kubectl get nodes
NAME                STATUS   ROLES    AGE    VERSION
phoenix-pool-bqk5   Ready    <none>   113s   v1.15.3
phoenix-pool-bqkp   Ready    <none>   74s    v1.15.3
phoenix-pool-bqks   Ready    <none>   80s    v1.15.3
```

## Nginx Ingress with Let's Encrypt

Web Applications need to be accessible from outside of your cluster, and should be only accessible via HTTPS. We are going to accomplish this using [NGINX Ingress](https://github.com/kubernetes/ingress-nginx) and [Cert-Manager](https://github.com/jetstack/cert-manager). [This tutorial](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-with-cert-manager-on-digitalocean-kubernetes) was foundational in my understanding of how this worked.

The basic idea of this section is to provide Kubernetes the ability to easily link your application's container with a load balancer, and automatically put a HTTPS reverse proxy in front of your application.

First, let's get NGINX Ingress up and running.

Run the following (taken from the [nginx ingress docs](https://kubernetes.github.io/ingress-nginx/deploy/)):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.25.1/deploy/static/mandatory.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.25.1/deploy/static/provider/cloud-generic.yaml
```

The above commands request creation of a load balancer. In a few minutes, the load balancer should be created, and you should get something similar:

```bash
$ kubectl get svc --namespace=ingress-nginx
NAME            TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)                      AGE
ingress-nginx   LoadBalancer   10.245.83.98   178.128.128.176   80:31168/TCP,443:31958/TCP   2m41s
```

Make note of the EXTERNAL-IP. We will reference that shortly.

It's time to install cert-manager. Run the following (taken from [the cert manager docs](https://docs.cert-manager.io/en/latest/getting-started/install/kubernetes.html)):

```bash
kubectl create namespace cert-manager
kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v0.10.0/cert-manager.yaml
```

Next, create the following file named `prod_issuer.yaml`:

```yaml
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: YOUR_EMAIL_HERE
    privateKeySecretRef:
      name: letsencrypt-prod
    http01: {}
```

only replacing `YOUR_EMAIL_HERE` with your email. This is a necessary config file for cert-manager that let's you add annotations to automatically request certs from let's encrypt.

Apply the file with `kubectl apply -f prod_issuer.yaml`

## DNS

We need to point two things to domains you control: a private docker registry and your phoenix application. If you already have a domain you control, you should create two different A records pointing to your EXTERNAL-IP and skip to the next section.

Create an account at [https://freedns.afraid.org](https://freedns.afraid.org/subdomain). This is free for what we want to do with it.

When that is completed, create two `A` records at the [subdomains](https://freedns.afraid.org/subdomain/edit.php) page.

- The type needs to be `A`.
- The subdomain can be whatever as long as you record it.
- The domain can be whatever as long as you record it.
- The destination should be the EXTERNAL-IP from above.

In my case, the output of this page looks like:

```text
phoenix1234.mooo.com A 178.128.128.176
registry1234.mooo.com A 178.128.128.176
```

It'll take some time to propagate.

## Private Docker Registry

Kubernetes is a container management system, so we are going to need a place to keep our containers. There are many ways to approach this. [Gitlab](https://gitlab.com) has a free container registry. [Dockerhub](https://hub.docker.com/) offers a free private repository per account. [Github](https://github.com/features/package-registry) has an invite only beta registry.

If you can `docker push` to a registry, feel free to skip to the next section. There are some advantages to controlling your own private docker registry, like having your images live in the same data center as your cluster. Those advantages likely do not outweigh managing another piece of infrastructure if you have an existing solution.

First, create a [Digital Ocean Space](https://cloud.digitalocean.com/spaces/new). This is equivalent to S3, and will be the backing storage for our private registry.

- Try putting it in the same region your cluster is in
- CDN is not necessary
- Restrict File Listing
- Pick any name for the unique name, just make note of it. Mine is `test-phoenix-kubernetes`

After that has been created, create a new [spaces api key](https://cloud.digitalocean.com/account/api/). The top generated string is your access key, the bottom one is the secret key. Run the following with those values:

```bash
echo -n YOUR_ACCESS_KEY > access_key
echo -n YOUR_SECRET_KEY > secret_key
```

New lines in env vars and secrets have bitten me before, so, the `-n` is necessary.

- Next, create a namespace for your registry with: `kubectl create namespace registry`
- Next, create an authentication file: `htpasswd -cB htpasswd admin`, entering your password when the prompt tells you to. (Note, the `-B` is for bcrypt, and it's poorly documented that this is required for the Docker registry)
- Create a kubernetes secret for all authentication: `kubectl create secret --namespace registry generic auth --from-file=./htpasswd --from-file=./access_key --from-file=./secret_key`

Create a registry.yaml with the following values:

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    app: registry
  name: registry
  namespace: registry
spec:
  replicas: 1
  strategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
      - name: registry
        image: registry:2
        resources:
          requests:
            memory: "512Mi"
            cpu: "300m"
          limits:
            memory: "550Mi"
            cpu: "350m"
        ports:
        - containerPort: 5000
        env:
          - name: REGISTRY_AUTH
            value: "htpasswd"
          - name: REGISTRY_AUTH_HTPASSWD_PATH
            value: "/auth/htpasswd"
          - name: REGISTRY_AUTH_HTPASSWD_REALM
            value: "Registry Realm"
          - name: REGISTRY_STORAGE
            value: "s3"
          - name: REGISTRY_STORAGE_S3_ACCESSKEY
            valueFrom:
              secretKeyRef:
                name: auth
                key: access_key
          - name: REGISTRY_STORAGE_S3_BUCKET
            value: "test-phoenix-kubernetes"  # REPLACE WITH YOUR OWN
          - name: REGISTRY_STORAGE_S3_REGION
            value: "sfo2" # REPLACE WITH YOUR REGION
          - name: REGISTRY_STORAGE_S3_REGIONENDPOINT
            value: "sfo2.digitaloceanspaces.com" # REPLACE WITH YOUR REGION ENDPOINT
          - name: REGISTRY_STORAGE_S3_SECRETKEY
            valueFrom:
              secretKeyRef:
                name: auth
                key: secret_key
        volumeMounts:
          - name: auth
            mountPath: /auth
      volumes:
        - name: auth
          secret:
            secretName: auth
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: registry
spec:
  selector:
    app: registry
  ports:
  - name: "5000"
    port: 5000
    targetPort: 5000
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: registry-ingress
  namespace: registry
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"
    certmanager.k8s.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - registry1234.mooo.com # REPLACE
    secretName: letsencrypt-prod
  rules:
  - host: registry1234.mooo.com # REPLACE
    http:
      paths:
      - backend:
          serviceName: registry
          servicePort: 5000
```

Replace the values where there is a # REPLACE comment with values from your registry.

Ensure that the DNS entry you've created in the above section resolves to your EXTERNAL-IP with `dig HOSTNAME`. If this does not, wait until DNS propagation finishes (which can take a while), and then continue. Part of the next step is certificate issuing by let's encrypt, which needs to reach your kubernetes cluster via the hostname.

Run `kubectl apply -f registry.yaml` with the changes you have made.

After a minute or two, run `kubectl get pods -n registry` which should result in something similar to:

```text
NAME                        READY   STATUS    RESTARTS   AGE
registry-dfd5d4c94-7kc2m    1/1     Running   0          14s
```

If you see something like `cm-acme-http-solver`, that's fine! Wait a few minutes and run the same command, it shouldn't be there anymore.

To verify that your registry is working, run:

```shell
docker login YOUR_REGISTRY_HOSTNAME # login with the username and password you created in the htpasswd command
docker pull elixir:1.9
docker tag elixir:1.9 YOUR_REGISTRY_HOSTNAME/admin/elixir:1.9
docker push YOUR_REGISTRY_HOSTNAME/admin/elixir:1.9
```

## A Brief Note about Troubleshooting

If things are not working at any point, my go to debugging commands are: `kubectl get pods`, `kubectl logs POD-ID`, `kubectl describe pod POD-ID`, and those should hopefully give you enough output to begin searching for a fix.

## Creating a Managed Database

Our Phoenix Application is going to be backed by a managed Postgres instance. [Navigate here](https://cloud.digitalocean.com/databases/new) to create one. Pick a $15/month instance in the data center nearest you. It should take a few minutes to be provisioned.

When it's done being created, add a user by clicking the "Users & Databases" tab. It will auto generate a password for you. In my case, my user is `phoenix_test_project`. Record the auto-generated password somewhere. In a production system, you'd want to create this user via the `psql` client, to be able to have fine control over their role's ability.

Create a database via the UI on the same page called `phoenix_test_project` as well.

Finally, go to the Settings tab, and add your Kubernetes cluster and your computer's IP address to the trusted sources section.

Note: It's possible to deploy Postgres yourself on Kubernetes to save costs; I have not done this though, and prefer paying to not worry about managing it properly.

## Creating a Phoenix App

It's finally time to create your Phoenix application! If you need help installing Phoenix and Elixir, [follow this guide](https://hexdocs.pm/phoenix/installation.html#content). Create your phoenix application with `mix phx.new kubernetes_phoenix` and `cd` into that directory.

We're going to be using [Elixir 1.9 releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html) for this. The [Phoenix documentation](https://hexdocs.pm/phoenix/releases.html) is very comprehensive, so turn to that if you want to dive deeper. Run `mix release.init` to generate some release helpers.

As mentioned in the [phoenix documentation](https://hexdocs.pm/phoenix/releases.html), add this file at `lib/release.ex` to deal with migrations:

```elixir
defmodule KubernetesPhoenix.Release do
  @app :kubernetes_phoenix

  def migrate do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.load(@app)
    {:ok, _} = Application.ensure_all_started(@app) # This is not in the phoenix documentation, but it's necessary to ensure :ssl is started
    Application.fetch_env!(@app, :ecto_repos)
  end
end
```

Also per the Phoenix documentation:

- Rename config/prod.secret.exs to config/releases.exs: `mv config/prod.secret.exs config/releases.exs`
- In config/releases.exs, change `use Mix.Config` to `import Config`
- Remove `import_config "prod.secret.exs"` from `prod.exs`
- Uncomment `config :kubernetes_phoenix, KubernetesPhoenixWeb.Endpoint, server: true` from `releases.exs`
- Uncomment `ssl: true,` from `releases.exs` for the Repo config.
- Add `:ssl` to the list of `extra_applications` in your `mix.exs` file, like this: `extra_applications: [:logger, :runtime_tools, :ssl]`. This is to ensure Ecto can talk to Postgres over SSL.
- Change "example.com" in `prod.exs` to the DNS name you chose earlier. Mine looks like `url: [host: "phoenix1234.mooo.com", port: 80],`
  - Don't worry about the port: 80 in this section. We are using NGINX and Cert-Manager to ensure traffic is encrypted via TLS.

## Secret Configurations

Let's create a Kubernetes namespace and generate some secrets our application will need:

```bash
kubectl create namespace phoenix
mix phx.gen.secret | tr -d "\n" > secret_key_base # New lines are the worst.
echo -n "ecto://USERNAME:PASSWORD@HOSTNAME:PORT/DATABASE" > postgres_url
# for example, mine was echo -n "ecto://phoenix_test_project:really_secure_password@private-test-phoenix-cluster-do-user-6447302-0.db.ondigitalocean.com:25060/phoenix_test_project" > postgres_url
kubectl create secret --namespace phoenix generic phoenix-secrets --from-file=./secret_key_base --from-file=./postgres_url
```

We need to create a secret that allows Kubernetes to pull from our private registry. The following is from [the kubernetes docs](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/#create-a-secret-by-providing-credentials-on-the-command-line). Fill out the values for your private docker registry.

```bash
kubectl create secret --namespace phoenix docker-registry regcred --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>
```

## Creating and Pushing a Docker Image

Add this Dockerfile to your application. (Taken from the [Phoenix Docs](https://hexdocs.pm/phoenix/releases.html))

```docker
FROM elixir:1.9.0-alpine as build
RUN apk add --update build-base git npm
RUN mkdir /app
WORKDIR /app
RUN mix local.hex --force && \
    mix local.rebar --force
ENV MIX_ENV=prod
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get
RUN mix deps.compile
COPY assets assets
RUN cd assets && npm install && npm run deploy
RUN mix phx.digest
COPY priv priv
COPY lib lib
RUN mix compile
COPY rel rel
RUN mix release

FROM alpine:3.9 AS app
RUN apk add --update bash openssl
RUN mkdir /app
WORKDIR /app
COPY --from=build /app/_build/prod/rel/kubernetes_phoenix ./
RUN chown -R nobody: /app
USER nobody
ENV HOME=/app
CMD ["bin/kubernetes_phoenix", "start"]
```

Run the following, substituting `registry1234.mooo.com` with your private container registry:

```bash
docker build . -t registry1234.mooo.com/admin/kubernetes_phoenix:latest
docker push registry1234.mooo.com/admin/kubernetes_phoenix:latest
```

## Database Migrations

Our database migrations will be done with Kubernetes jobs. Create a migrate_job.yaml with the following:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-job-latest
  namespace: phoenix
spec:
  template:
    spec:
      containers:
        - name: migrate-latest
          image: registry1234.mooo.com/admin/kubernetes_phoenix:latest # use your own registry
          command:
            [
              "bin/kubernetes_phoenix",
              "eval",
              "KubernetesPhoenix.Release.migrate",
            ]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: phoenix-secrets
                  key: postgres_url
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef:
                  name: phoenix-secrets
                  key: secret_key_base
      imagePullSecrets:
        - name: regcred
      restartPolicy: Never
```

Run the migrations with: `kubectl apply -f migrate_job.yaml`. Then, run `kubectl get pods -n phoenix`. If all went well, you'll get output similar to:

```bash
$ kubectl get pods -n phoenix
NAME                       READY   STATUS      RESTARTS   AGE
migrate-job-latest-vgh6z   0/1     Completed   0          97s
```

You can check the logs by using `kubectl logs -n phoenix POD-name`, like:

```bash
$ kubectl logs -n phoenix migrate-job-latest-vgh6z
21:00:47.312 [info] Running KubernetesPhoenixWeb.Endpoint with cowboy 2.6.3 at :::4000 (http)
21:00:47.324 [info] Access KubernetesPhoenixWeb.Endpoint at http://phoenix1234.mooo.com
21:00:47.683 [info] Already up
```

Delete the job after it completes: `kubectl delete -f migrate_job.yaml`

## Running the Application

Create an `application.yaml` that has the following:

```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: phoenix
  namespace: phoenix
spec:
  selector:
    matchLabels:
      app: phoenix
  replicas: 2
  strategy:
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 2
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: phoenix
    spec:
      containers:
        - name: phoenix
          image: registry1234.mooo.com/admin/kubernetes_phoenix:latest # use your own registry
          resources:
            requests:
              memory: "512Mi"
              cpu: "300m"
            limits:
              memory: "550Mi"
              cpu: "350m"
          ports:
            - containerPort: 4000
          livenessProbe:
            httpGet:
              path: /
              port: 4000
            initialDelaySeconds: 45
            successThreshold: 1
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /
              port: 4000
            initialDelaySeconds: 0
            successThreshold: 1
            failureThreshold: 3
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: phoenix-secrets
                  key: postgres_url
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef:
                  name: phoenix-secrets
                  key: secret_key_base
      imagePullSecrets:
        - name: regcred
---
apiVersion: v1
kind: Service
metadata:
  name: phoenix-service
  namespace: phoenix
spec:
  selector:
    app: phoenix
  ports:
    - protocol: TCP
      port: 4000
      name: web
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: phoenix-ingress
  namespace: phoenix
  annotations:
    kubernetes.io/ingress.class: nginx
    certmanager.k8s.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - phoenix1234.mooo.com  # Use your own hostname
      secretName: letsencrypt-prod
  rules:
    - host: phoenix1234.mooo.com # Use your own hostname
      http:
        paths:
          - backend:
              serviceName: phoenix-service
              servicePort: 4000

```

Deploy the application with: `kubectl apply -f application.yaml`. Then, run `kubectl get pods -n phoenix`. If all went well, you'll have output that looks like this after a minute or two:

```text
NAME                      READY   STATUS    RESTARTS   AGE
phoenix-679fbdbd5-4ws6q   1/1     Running   0          1m18s
phoenix-679fbdbd5-5cwhz   1/1     Running   0          1m18s
```

Your website should now be available at the dns address you've picked! In my case, it was available at `http://phoenix1234.mooo.com` (It is not there anymore.)

## Next Steps

Hopefully things went smoothly for you! Please leave a comment if they did not, and [star the base repo](https://github.com/djquan/kubernetes-phoenix) if it did!

There are a lot of exciting things you can do with your newly deployed application. Some ideas are:

- [Use Digital Ocean's Advanced Metrics](https://www.digitalocean.com/docs/kubernetes/how-to/monitor-advanced/)
- [Install Linkerd](https://linkerd.io/)
- Use [Libcluster](https://github.com/bitwalker/libcluster) to get Erlang node clustering working. It's not hard! Take a look at [this commit](https://github.com/djquan/budget.sh/commit/e08e893ee76df9e1c47805f562d58d9f6342ed7a) for some guidance.
- [Get Observer](/blog/using-erlangs-observer-in-kubernetes-for-an-elixir-release/) working
- [Get Continuos Delivery](https://github.com/djquan/budget.sh/blob/7b445a77fc7cd2b2954ea50506f2fc8585aa9949/.github/workflows/main.yml#L39-L83) working in your CI platform
