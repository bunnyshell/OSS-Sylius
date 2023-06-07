#!/bin/sh
set -e

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- php-fpm "$@"
fi

php bin/console cache:clear

if [ "$1" = 'php-fpm' ] || [ "$1" = 'bin/console' ]; then
	mkdir -p var/cache var/log var/sessions public/media

	# @note: certain filesystems might not support setfacl
	setfacl -R -m u:www-data:rwX -m u:"$(whoami)":rwX var public/media || true
 	setfacl -dR -m u:www-data:rwX -m u:"$(whoami)":rwX var public/media || true

	if [ "$APP_ENV" != 'prod' ]; then
		composer install --prefer-dist --no-progress --no-interaction
		php bin/console assets:install --no-interaction
		php bin/console sylius:theme:assets:install public --no-interaction
	fi

	# @note: this is not needed for a Kubernetes setup because the migrations would run as an init container.
	while ping -c1 migrations >/dev/null 2>&1;
	do
	    (>&2 echo "Waiting for Migrations container to finish")
	    sleep 1;
	done;
fi

exec docker-php-entrypoint "$@"
