#
# Author:: Brian Matthews (<brian@btmatthews.com>)
# Cookbook Name:: archive
# Provider:: default
#
# Copyright 2015, Brian Matthews
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include ::Archive::Helper

def whyrun_supported?
	true
end

action :unpack do
	converge_by("Unpack archive #{ @new_resource }") do
		unpack_archive
	end
	new_resource.updated_by_last_action(true)
end

def load_current_resource
	@current_resource = Chef::Resource::Archive.new(@new_resource.name)
	@current_resource.name(@new_resource.name)
	@current_resource.source(@new_resource.source)
	@current_resource.path(@new_resource.path)
	@current_resource.owner(@new_resource.owner)
	@current_resource.group(@new_resource.group)
	@current_resource.mode(@new_resource.mode)
	@current_resource.dir_mode(@new_resource.dir_mode)
	@current_resource.exclusions(@new_resource.exclusions)
	@current_resource.inclusions(@new_resource.inclusions)
	@current_resource.cookbook(@new_resource.cookbook)
	@current_resource.strip(@new_resource.strip)
end

private

def unpack_archive
	source = create_archive_source(@new_resource.source, run_context, cookbook_name)
	uncompressor = create_archive_uncompressor(source, @new_resource.path)
	uncompressor.owner = @new_resource.owner
	uncompressor.group = @new_resource.group
	uncompressor.mode = @new_resource.mode
	uncompressor.dir_mode = @new_resource.dir_mode
	uncompressor.exclusions = @new_resource.exclusions
	uncompressor.inclusions = @new_resource.inclusions
	uncompressor.strip = @new_resource.strip
	uncompressor.uncompress
end
