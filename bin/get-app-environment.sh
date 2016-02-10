#!/bin/bash

MISSING_STUFF=false

if [ -z "${APP}" ]; then
	>&2 echo "No APP specified"
	MISSING_STUFF=true
fi
if [ -z "${ENVIRONMENT}" ]; then
	>&2 echo "No ENVIRONMENT specified"
	MISSING_STUFF=true
fi

if [ -z "${S3LOCATION}" ]; then
	>&2 echo "No S3LOCATION specified, using local filesystem to fetch keys"

	if [ ! -f keys/private.key ]; then
		>&2 echo "No private key found, unable to decrypts"
	fi
	if [ ! -f keys/public.key ]; then
		>&2 echo "No public key found, unable to verify signatures"
	fi
else
	>&2 echo "S3LOCATION specified, fetching keys from s3"

	mkdir s3keys
	/usr/bin/aws s3 sync s3keys/ s3://${S3LOCATION}

	if [ ! -f s3keys/private.key ]; then
		>&2 echo "No (s3) private key found, unable to decrypts"
	fi
	if [ ! -f s3keys/public.key ]; then
		>&2 echo "No (s3) public key found, unable to verify signatures"
	fi
fi

if [ "${MISSING_STUFF}" == "true" ]; then
	exit 1
fi

if [ -z "${S3LOCATION}" ]; then
	# Import GPG keys
	gpg2 --import keys/private.key 2>/dev/null
	gpg2 --import keys/public.key 2>/dev/null
else
	# Import GPG keys
	gpg2 --import s3keys/private.key 2>/dev/null
	gpg2 --import s3keys/public.key 2>/dev/null
fi

for KEY in $(etcdctl ls /env/${APP}/${ENVIRONMENT} | sort); do
	BASE_KEY=$(basename ${KEY})
	VALUE=$(etcdctl get ${KEY})

	# Attempt decryption
	DECRYPTED_VALUE=$(printf -- '-----BEGIN PGP MESSAGE-----\n\n%s\n-----END PGP MESSAGE-----\n' ${VALUE} | gpg2 --decrypt 2>/dev/null)
	if [ $? -eq 0 ]; then
		# This is a PGP block, is it for _this_ key?
		echo ${DECRYPTED_VALUE} | grep -qi ^${BASE_KEY}=
		if [ "$?" -eq 0 ]; then
			# Valid ciphertext, emit decrypted value:
			DECRYPTED_VALUE=$(echo ${DECRYPTED_VALUE} | sed "s/^${BASE_KEY}=//I")
		else
			# This is ciphertext stolen from another key
			DECRYPTED_VALUE=""
		fi
	else
		DECRYPTED_VALUE=""
	fi

	if [ -n "${DECRYPTED_VALUE}" ]; then
		echo ${BASE_KEY}=${DECRYPTED_VALUE}
	else
		echo ${BASE_KEY}=${VALUE}
	fi
done

