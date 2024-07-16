# frozen_string_literal: true

require "thor"
require "json"
require "yaml"
require "pathname"

module Massdriver
  class Cli < Thor
    include Thor::Actions

    CONFIG_FILE = "#{Pathname.getwd}/mass.yml"

    def self.default_options
      # Enforce configuring this from a local yaml file based on working dir
      @default_options ||= Thor::CoreExt::HashWithIndifferentAccess.new(
        if File.exist?(CONFIG_FILE)
          puts "Using configuration file #{CONFIG_FILE}"
          YAML.load_file(CONFIG_FILE) || {}
        else
          {repo: "", ref: "main", image_repo: "", migrate_app: "", apps: []}
        end
      )
    end

    class_option :target, aliases: "-t", desc: "Target environment to deploy to (staging/prod)", required: true
    class_option :noop, type: :boolean, default: false, desc: "Noop when calling massdriver commands"

    desc "deploy", "Deploys the App"
    long_desc <<-LONGDESC
    `massdriver deploy` will handle deploying the latest or (optionally) passed revision to the target environment.

    You must specify the target environment at all times.
    \x5> $ massdriver deploy -t staging

    You can also change which apps are being deployed in the event that you only need to deploy a subset.
    \x5> $ massdriver deploy -t staging -a strailsbg shoptracker

    You can additionally utilize the `--noop` option to prevent any calls to go to massdriver
    \x5> $ massdriver deploy -t prod --noop
    LONGDESC
    option :apps, aliases: "-a", type: :array, default: default_options[:apps], desc: "Apps to deploy", required: true
    option :ref, aliases: "-r", default: default_options[:ref], desc: "ref to deploy (commit/tag/branch)"
    option :repo, default: default_options[:repo], required: true, desc: "git repo"
    option :image_repo, default: default_options[:image_repo], required: true, desc: "ECR repo to validate image availability"
    option :migrate, aliases: "-m", type: :boolean, default: true, desc: "Run Migrations"
    option :migrate_app, default: default_options[:migrate_app]
    def deploy
      repo = "#{options[:repo]}"
      commit = git_sha(repo, options[:ref])

      # Confirm the image exists for deployment
      if commit.empty? || commit != get_ecr_sha(options[:image_repo], "sha-#{commit}")
        say_status(:missing, "image missing for ref '#{options[:ref]}' (sha: #{commit})", :red)

        abort("Cancelling deployment! Image not available for deployment")
      end

      apps = options[:apps]
      apps.unshift(options[:migrate_app]) if options[:migrate]

      apps.each do |app|
        deploy_app(options[:target], app, commit)
      end
    end

    desc "patch", "Patches the given apps with the key/value pair"
    long_desc <<-LONGDESC
    `massdriver patch` will handle patching the given application(s) with the key/value pair(s) and then deploy the apps as well.
    The value will always be hidden to prevent accidentally leaking passwords into the history.

    You must specify the target environment at all times.
    \x5> $ massdriver patch -t staging -k email_pw_joe -k image.tag

    You can also change which apps are being deployed in the event that you only need to deploy a subset.
    \x5> $ massdriver patch -t staging -a strailsbg shoptracker -k email_pw_joe

    You can additionally utilize the `--noop` option to prevent any calls to go to massdriver
    \x5> $ massdriver patch -t prod -k email_pw_joe --noop
    LONGDESC
    option :deploy, type: :boolean, default: true
    option :apps, aliases: "-a", type: :array, default: default_options[:apps] + Array(default_options[:migrate_app]), desc: "Apps to patch"
    option :config_key, aliases: "-k", required: true, repeatable: true
    def patch
      config_map = options[:config_key].map do |k|
        puts "\x5" # line break between prompts
        [k, ask("What is the value for #{k}?", echo: false)]
      end.to_h

      puts "\x5" # line break after last secret ask
      options[:apps].each do |app|
        patch_app(options[:target], app, config_map)
        deploy_app(options[:target], app) if options[:deploy]
      end
    end

    no_tasks do
      def git_sha(repo, ref)
        run("git ls-remote git@github.com:#{repo}.git #{ref} | tail -n1 | cut -f1", capture: true).strip
      end

      def get_ecr_sha(repository, commit)
        say_status(:help, "if this next command exits the run, run the command manually to check for stderr", :yellow)
        images = run("aws ecr describe-images --repository-name #{repository} --image-ids imageTag=#{commit} --query 'imageDetails[0].imageTags'", capture: true)

        unless images.nil?
          sha = JSON.parse(images).select { |t| t.start_with?("sha") }.first
          abort("Unable to get SHA for latest image") if sha.nil?
          return sha[4..-1].strip
        end

        abort("Error reading from ECR")
      end

      def deploy_apps(target, apps, commit)
        apps.each do |app|
          deploy_app(target, app, commit)
        end
      end

      def patch_app(target, app, updates = {})
        patch = "mass app patch infra-#{target}-#{app}"
        updates.each do |k, v|
          patch += " --set='.#{k}=\"#{v}\"'"
        end

        if options[:noop]
          say_status(:noop, patch)
        else
          run(patch)
        end
      end

      def deploy_app(target, app, commit = nil)
        deploy = "mass app deploy infra-#{target}-#{app}"

        patch_app(target, app, "image.tag" => "sha-#{commit}") unless commit.nil?

        if options[:noop]
          say_status(:noop, deploy)
        else
          run(deploy)
        end
      end
    end

    def self.exit_on_failure?
      true
    end
  end
end
