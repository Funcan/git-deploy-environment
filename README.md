# Git-Deploy-Environment #

Optional component of [git-deploy](https://github.com/pebble/git-deploy) ecosystem for reading application environment variables stored in etcd.

This supports decryption and verification of secret values generated by git-deploy's ```secret``` helper script.


Creating secrets:

```
ssh git@ci.someserver.com genkey staging-some-app
SECRET=$(ssh git@ci.someserver.com secret staging-some-app FOO=bar)
etcdctl set /env/some-app/staging/FOO $SECRET
```



Then in the systemd service definition:

```
ExecStartPre=/usr/bin/docker run --rm -e APP=some-app -e ENVIRONMENT=%i -v /home/core/git-deploy-keys:/home/decrypt/keys:ro pebbletech/git-deploy-environment > /home/core/some-app-env
ExecStart=/usr/bin/docker run --rm --name some-app --env-file=/home/core/some-app-env your-registry/some-app
ExecStartPost=/bin/sh -c "sleep 5 && echo '' > /home/core/some-app-env"
ExecStop=/usr/bin/docker stop some-app
```

