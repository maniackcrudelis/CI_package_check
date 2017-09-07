#!/bin/bash

# List all apps from official and community list
# And build a job

#=================================================
# Grab the script directory
#=================================================

if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

#=================================================
#=================================================
# JENKINS SPECIFIC PART
#=================================================
# This part must be duplicated and rewrite to be used with another software than Jenkins
# Then change all calls of these functions

jenkins_job_path="/var/lib/jenkins/jobs"
jenkins_url=localhost:8080

jenkins_java_call="sudo java -jar /var/lib/jenkins/jenkins-cli.jar -noCertificateCheck -s http://$jenkins_url"

JENKINS_BUILD_JOB () {
	# Build a jenkins job

	base_jenkins_job="$script_dir/jenkins/jenkins_job"

	# By default, use a standard job
	cp "${base_jenkins_job}.xml" "${base_jenkins_job}_load.xml"

	# If it's not the default architecture
	if [ "$architecture" != "default" ]
	then
		# Use the arch job squeleton
		cp "${base_jenkins_job}_arch.xml" "${base_jenkins_job}_load.xml"

	# If it's not the stable type of test
# 	elif [ "$type_test" != "stable" ]
# 	then
# 		# Use the nostable job squeleton
# 		cp "${base_jenkins_job}_nostable.xml" "${base_jenkins_job}_load.xml"
	fi

	# Replace the url of the git repository
	sed --in-place "s@__REPOGIT__@$repo@g" "${base_jenkins_job}_load.xml"

	# Replace the path of analyseCI script
	sed --in-place "s@__PATH__@$(dirname "$script_dir")@g" "${base_jenkins_job}_load.xml"

	# Determine a day for the monthly test (stable only)
# 	sed --in-place "s@__DAY__@$(( $RANDOM % 30 +1 ))@g" "${base_jenkins_job}_load.xml"

	# Put the job name, without its architecture (arch only)
# 	sed --in-place "s@__PARENT_NAME__@$(echo "$job_name" | sed "s@ .~.*~.@@")@g" "${base_jenkins_job}_load.xml"

	# Replace the type of test (Testing or unstable only)
# 	sed --in-place "s@__TYPE__@$type_test@g" "${base_jenkins_job}_load.xml"

	# For unstable type, remove the trigger on all commmunity apps
# 	if [ "$type_test" = "unstable" ]
# 	then
# 		sed --in-place 's@.*\*</spec>@#&@' "${base_jenkins_job}_load.xml"
# 	fi

	# Create the job in jenkins
	$jenkins_java_call create-job "$job_name" < "${base_jenkins_job}_load.xml"

	# For stable type, start a test after adding it
# 	if [ "$type_test" = "stable" ] && [ "$architecture" = "default" ]
# 	then
# 		$jenkins_java_call build "$job_name"
# 	fi
}

JENKINS_REMOVE_JOB () {
	# Remove a jenkins job
	$jenkins_java_call delete-job "$job_name"
}

JENKINS_LIST_JOBS () {
	# List current jobs only for the specified list
	$jenkins_java_call list-jobs | grep --ignore-case "($list)" > "$current_jobs"
}

GET_GIT_URL_JENKINS () {
	# Get the url of the git repository from the job file
	local url=$(grep "<url>" "/var/lib/jenkins/jobs/$app/config.xml" | cut --delimiter='>' --fields=2 | cut --delimiter='<' --fields=1)
	echo "$url"
}

#=================================================
# END OF JENKINS SPECIFIC PART
#=================================================
#=================================================

# Path of directory which contains the jobs
# Replace this variable if you use another software than Jenkins
job_path=$jenkins_job_path

#=================================================
# Get the architecture for the current job
#=================================================

get_arch () {
	architecture="$(echo $(expr match "$appname" '.*\((~.*~)\)') | cut --delimiter='(' --fields=2 | cut --delimiter=')' --fields=1)"
	# Fix at 'default' is none architecture is specified.
	test -n "$architecture" || architecture=default
}

#=================================================
# Build and remove a job
#=================================================

BUILD_JOB () {

	# Get the architecture for this job
	get_arch

# 	if [ "$architecture" == "default" ]
# 	then
# 		type_of_test="stable testing unstable"
# 	else
		type_of_test="stable"
# 	fi

	# Build a job for stable, testing and unstable
	for type_test in $type_of_test
	do
		job_name="$appname"
		if [ "$type_test" != "stable" ]
		then
			job_name="$appname ($type_test)"
		fi

		# Build a job
		JENKINS_BUILD_JOB
	done
}

REMOVE_JOB () {

	# Get the architecture for this job
	get_arch

# 	if [ "$architecture" == "default" ]
# 	then
# 		type_of_test="stable testing unstable"
# 	else
		type_of_test="stable"
# 	fi

	# Remove the jobs for stable, testing and unstable
	for type_test in $type_of_test
	do
		job_name="$appname"
		local log_type_path=""
		if [ "$type_test" != "stable" ]
		then
			job_name="$appname ($type_test)"
			log_type_path="$type_test/"
		fi
		JENKINS_REMOVE_JOB

		# Build the log names
		if [ "$architecture" = "default" ]; then
			local arch_log=""
		else
			local arch_log="$architecture"
		fi
		# From the repository, remove http(s):// and replace all / by _ to build the log name
		local app_log=$(echo "${repo#http*://}" | sed 's@/@_@g')$arch_log.log
		# The complete log is the same of the previous log, with complete at the end.
		local complete_app_log=$(basename --suffix=.log "$app_log")_complete.log

		# Remove the logs for this job
		sudo rm --force "$script_dir/../logs/${log_type_path}${app_log}"
		sudo rm --force "$script_dir/../logs/${log_type_path}${complete_app_log}"
	done
}

#=================================================
# Standard functions
#=================================================

BUILD_LIST () {
	# Build a list of all jobs currently in the CI for this list

	# List current jobs only for the specified list
	JENKINS_LIST_JOBS

	# Purge the list of job
	> "$parsed_current_jobs"

	# Read each app listed by {JENKINS}_LIST_JOBS
	while read app
	do
		local repo=$(GET_GIT_URL_JENKINS)
		# Print a list with each app and its repository
		echo "$repo;$app" >> "$parsed_current_jobs"
	done < "$current_jobs"

}

PARSE_LIST () {
	# Build the list of YunoHost apps

	# Download the list from YunoHost github
	wget -nv https://raw.githubusercontent.com/YunoHost/apps/master/$list.json -O "$script_dir/$list.json"

	# Build the grep command. To list only the git repository of each app on the json file
	if [ "$list" = "official" ]
	then
		grep_cmd="grep '\\\"url\\\":' \"$script_dir/$list.json\" | cut --delimiter='\"' --fields=4"
	else
		grep_cmd="grep '\\\"state\\\": \\\"working\\\"' \"$script_dir/$list.json\" -A1 | grep '\\\"url\\\":' | cut --delimiter='\"' --fields=4"
	fi

	# Purge the list
	> "$ynh_list"

	local repo=""
	# Parse each git repository
	while read repo
	do
		# Get the name of the app
		appname="$(basename --suffix=_ynh $repo)"

		# Then add the name of the list, with the first character in uppercase
		appname="$appname ($(echo ${list:0:1} | tr [:lower:] [:upper:])${list:1})"

		# Print the repo and the name of the job into the list
		echo "$repo;${appname}" >> "$ynh_list"

		# Check the other architectures
# 		for architecture in x86-64b x86-32b ARM
# 		do
# 			# If this architecture is set to 1 in the config file
# 			if [ "$(cat "$script_dir/auto.conf" | grep "${architecture}=" | cut --delimiter='=' --fields=2)" = "1" ]
# 			then
# 				# Add a line for this architecture into the list
# 				echo "$repo;${appname} (~${architecture}~)" >> "$ynh_list"
# 			fi
# 		done
	done <<< "$(eval $grep_cmd)"
}

CLEAR_JOB () {
	# Remove the jobs that not anymore in the YunoHost list

	# Check each app in the list of current jobs
	while read app
	do

		# Check if this app can be found in the yunohost list
		if ! grep --quiet "^$app$" "$ynh_list"
		then
			# Get the name of this app
			appname=$(grep "^$app$" "$parsed_current_jobs" | cut --delimiter=';' --fields=2)

			echo "Remove the jobs for the application $appname" | tee -a "$message_file"

			# Archive the job and its history before remove it
			sudo tar --create --preserve-permissions --gzip --file "$job_path/$appname $(date +%d-%m-%Y).tar.gz" --directory "$job_path" "$appname"

			# Remove the jobs for stable, testing and unstable
			REMOVE_JOB
		fi
	done < "$parsed_current_jobs"
}

ADD_JOB () {
	# Add the jobs that not in the current jobs

	# Check each app in the list of current jobs
	while read app
	do

		# Check if this app can be found in the list of current jobs
		if ! grep --quiet "^$app$" "$parsed_current_jobs"
		then
			# Get the name of this app
			appname=$(echo "$app" | cut --delimiter=';' --fields=2)
			# Get the repository
			repo=$(echo "$app" | cut --delimiter=';' --fields=1)

			echo "Add the application $appname for the repository $repo" | tee -a "$message_file"

			# Build a job for stable, testing and unstable
			BUILD_JOB
		fi
	done < "$ynh_list"
}

#=================================================
# Define variables
#=================================================

ynh_list="$script_dir/ynh_list"
current_jobs="$script_dir/current_jobs"
parsed_current_jobs="$script_dir/parsed_current_jobs"
message_file="$script_dir/job_send"
# Purge the message file
> "$message_file"

# Work on the official list, then community list
for list in official community
do
	# Build a list of all jobs currently in the CI
	BUILD_LIST

	# Build the list of YunoHost apps from the official lists of apps
	PARSE_LIST

	# Remove the jobs that not anymore in the YunoHost list
	CLEAR_JOB

	# Add the jobs that not in the current jobs
	ADD_JOB
done

#=================================================
# Notify on xmpp apps room
#=================================================

# If the message file is not empty
# if [ -s "$message_file" ]
# then
# 
# 	# If the message has more than one line, store it into a pastebin
# 	if [ $(wc --lines "$message_file" | cut --delimiter=' ' --fields=1) -gt 1 ]
# 	then
# 		# Store the message into a pastebin
# 		paste=$(cat "$message_file" | yunopaste)
# 		# And send only its adress
# 		echo "Modification of apps list on our CI: $paste" > "$message_file"
# 	fi
# 
# 	xmpppost="$script_dir/xmpp_bot/xmpp_post.sh"
# 	# Send via xmpp only if the script was find
# 	if [ -e "$xmpppost" ]
# 	then
# 		"$xmpppost" "$(cat "$message_file")"
# 	fi
# fi
