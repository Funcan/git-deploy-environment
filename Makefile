NAME=git-deploy-environment
HUB_NAME=pebbletech/git-deploy-environment

TEST_KEY=testing

DOCKER_MACHINE=$(shell docker-machine active 2>/dev/null)

ifeq ("$(DOCKER_MACHINE)", "")
	TEMP_KEYS_DIR=$(PWD)/build/keys
else
	TEMP_KEYS_DIR=/home/docker/keys
endif

build: build/docker-image

build/docker-image:
	@mkdir -p build/
	@docker build -t $(NAME) .
	@docker inspect -f '{{.Id}}' $(NAME) > build/docker-image

test: build/docker-image
	# Start git-deploy, get a secret:
	docker run -d \
		--name $(NAME)-deploy \
		-v /dev/urandom:/dev/random \
		-e DEST=file:///backup_volume \
		-e PASSPHRASE=a_test_passphrase \
		registry-new.getpebble.com/pebble/git-deploy:master
	docker exec -t $(NAME)-deploy genkey $(TEST_KEY)
	docker exec -t $(NAME)-deploy secret $(TEST_KEY) PASSWORD=s0m3s3cr3t > build/PASSWORD.txt

	# Extract GPG keys (incl. sync to docker-machine for OSX)
	@mkdir -p build/keys/
	@docker exec $(NAME)-deploy gpg --export-secret-keys $(TEST_KEY) > build/keys/private.key
	@docker exec $(NAME)-deploy gpg --export git-deploy > build/keys/public.key
	@if [ -n "$(DOCKER_MACHINE)" ]; then \
		docker-machine ssh $(DOCKER_MACHINE) -- mkdir -p keys/; \
		for key in build/keys/*; do \
			KEY=`basename $$key`; \
			cat $${key} | docker-machine ssh $(DOCKER_MACHINE) -- cat \> keys/$${KEY}; \
		done \
	fi
	@docker kill $(NAME)-deploy

	# Start etcd:
	docker run -d \
		--name $(NAME)-etcd \
		--hostname=$(NAME)-etcd \
		deis/test-etcd:latest \
		etcd \
			--listen-client-urls http://0.0.0.0:4001 \
			--advertise-client-urls http://$(NAME)-etcd:4001
	while true; do \
		docker exec $(NAME)-etcd etcdctl cluster-health && break; \
		sleep 0.1; \
	done

	# Store keys, plaintext and encrypted:
	@docker exec $(NAME)-etcd etcdctl set /env/singlekey/test/FOO bar >/dev/null
	@docker exec $(NAME)-etcd etcdctl set /env/singlekey/test/FOZ baz >/dev/null
	@cat build/PASSWORD.txt | docker exec -i $(NAME)-etcd etcdctl set /env/singlekey/test/PASSWORD >/dev/null

	# Generate environment:
	docker run \
		--link $(NAME)-etcd:etcd \
		-e APP=singlekey \
		-e ENVIRONMENT=test \
		-e ETCDCTL_PEERS=http://etcd:4001 \
		-v $(TEMP_KEYS_DIR):/home/decrypt/keys \
		$(NAME) | tee build/environment.txt

	-docker kill $(NAME)-etcd

clean:
	echo $(DOCKER_MACHINE)
	rm -Rf build/
	-docker kill $(NAME)-etcd
	-docker kill $(NAME)-deploy
	-docker rm $(NAME)-etcd
	-docker rm $(NAME)-deploy

deploy:
	docker build -t $(HUB_NAME) .
	docker push $(HUB_NAME)

