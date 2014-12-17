#/bin/bash

trace() {
	echo "$1" # echo so it will be captured by logs
    eventHelper.py --msg "$1" --severity TRACE || true
}

warn() {
	echo "$1" # echo so it will be captured by logs
    eventHelper.py --msg "$1" --severity WARN || true
}

error_exit() {
	echo "$1" # echo so it will be captured by logs
    eventHelper.py --msg "$1" --severity ERROR || true
    #service nginx stop # stop nginx so env turns RED
    exit $2
}

is_rhel() {
	[ -f /usr/bin/yum ]
}

control_upstart_service() {
	if is_rhel; then
		initctl $2 $1
	else
		error_exit "Unknown upstart manager" 1
	fi
}

start_upstart_service() {
	control_upstart_service $1 start
}

stop_upstart_service() {
	control_upstart_service $1 stop
}

is_baked() {
  if [[ -f /etc/elasticbeanstalk/baking_manifest/$1 ]]; then
    true
  else
    false
  fi
}
