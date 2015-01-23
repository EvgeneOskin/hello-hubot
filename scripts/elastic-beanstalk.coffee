# Description:
#   Send request to elastic beasntalk
#
# Dependencies:
#   "aws-sdk": "2.1.7"
#   "octonode": "0.6.14"
#
#
# Configuration:
#
#
# Commands:
#   AWS_ACCESS_KEY_ID=".."
#   AWS_SECRET_ACCESS_KEY=".."
#   HUBOT_AWS_EB_REGION=".."
#   HUBOT_GITHUB_TOKEN=".."
#
# Author:
#   EvgeneOskin

github = require 'octonode'
uuid = require 'node-uuid'
AWS = require 'aws-sdk'


AWS.config.update {region: process.env.HUBOT_AWS_EB_REGION}
elasticbeanstalk = new AWS.ElasticBeanstalk
s3 = new AWS.S3
ghClient = github.client process.env.HUBOT_GITHUB_TOKEN

module.exports = (robot) ->

  robot.respond /eb describe environment (.+)/i, (msg) ->
    describe_app_env_status msg, msg.match[1]

  robot.respond(
    /eb deploy (.+) to (.+) (.+) with version (.+) and description (.*) s3 (.+)/i,
    (msg) ->
      url = msg.match[1]
      app = msg.match[2]
      env = msg.match[3]
      version = msg.match[4]
      desc = msg.match[5]
      bucket = msg.match[6]
      deploy_from_url msg, app, env, version, desc, bucket, url
  )

  robot.respond(
    /eb update repo (.+) rev (.+) path (.+) to (.+) (.+) with tag (.+) and description (.*) s3 (.+)/i,
    (msg) ->
      repository = msg.match[1]
      branch = msg.match[2]
      path = msg.match[3]
      app = msg.match[4]
      environment = msg.match[5]
      version = msg.match[6]
      desc = msg.match[7]
      bucket = msg.match[8]
      deploy_from_github(
        msg, app, environment, version, desc, repository, branch, path, bucket
      )
  )

  robot.respond /s3 list/i, (msg) -> s3_ls_buckets msg

  robot.respond /s3 put (.+) to (.+) as (.+)/i, (msg) ->
    s3_put_url msg, msg.match[1], msg.match[2], msg.match[3]


describe_app_env_status = (msg, environment) ->
  params =
    EnvironmentNames: [environment]
  elasticbeanstalk.describeEnvironments params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log(err, err.stack)
    else
      if data.Environments
        envObj = data.Environments[0]
        status = envObj.Status
        version = envObj.VersionLabel
        msg.send "#{environment}'s status is #{status} with version #{version}."
      else
        msg.send "Can not find such application and environment."

deploy_new_version = (msg, app, environment, version, desc, s3bucket, s3key) ->
  create_new_version msg, app, version, desc, s3bucket, s3key, ->
    deploy_version msg, version, environment


create_new_version = (msg, app, version, desc, s3bucket, s3key, cb) ->
  params =
    ApplicationName: app
    VersionLabel: version
    AutoCreateApplication: false
    Description: desc
    SourceBundle:
      S3Bucket: s3bucket
      S3Key: s3key

  elasticbeanstalk.createApplicationVersion params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log(err, err.stack)
    else
      msg.send "Created new app version #{version}"
      cb()

deploy_version = (msg, version, environment) ->
  params =
    VersionLabel: version
    EnvironmentName: environment

  elasticbeanstalk.updateEnvironment params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log(err, err.stack)
    else
      status_command = "eb describe environment #{environment}"
      msg.send "Please check the result later... use #{status_command}"

generate_s3_key = uuid.v4

deploy_from_url = (msg, app, environment, version, desc, url, bucket) ->
  s3_key = generate_s3_key()
  s3_put_url msg, url, bucket, s3_key, (key) ->
    deploy_new_version msg, app, environment, version, desc, bucket, key

deploy_from_github = (
  msg, app, environment, version, desc, repository, branch, path, bucket) ->
  s3_key = generate_s3_key()
  s3_put_object_from_github msg, repository, branch, path, bucket, s3_key, (key) ->
    deploy_new_version msg, app, environment, version, desc, bucket, key


s3_ls_buckets = (msg) ->
  s3.listBuckets (err, data) ->
    if err
      console.log err, err.stack
    else
      msg.send [i.Name for i in data.Buckets]

get_object_from_url = (msg, url, cb) ->
  msg.http(url).get() (err, res, body) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log(err, err.stack)
    else
      cb body

s3_put_object = (msg, object, bucket, key, cb) ->
  params =
    Bucket: bucket
    Key: key
    ACL: "authenticated-read"
    Body: object
  s3.putObject params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      msg.send "Puted object to s3! Nice work!"
      if cb
        cb()

s3_put_url = (msg, url, bucket, key, cb) ->
  get_object_from_url msg, url, (body) ->
    s3_put_object body, bucket, key, () -> cb key

get_object_from_github = (msg, repository, branch, path, cb) ->
  ghrepo = ghClient.repo repository
  ghrepo.contents path, branch, (err, data, headers) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      cb new Buffer data.content, data.encoding

s3_put_object_from_github = (msg, repository, branch, path, bucket, key, cb) ->
  get_object_from_github msg, repository, branch, path, (buffer) ->
    s3_put_object msg, buffer, bucket, key, () -> cb key
