# Description:
#   Send request to elastic beasntalk
#
# Dependencies:
#   "aws-sdk": "2.1.7"
#   "octonode": "0.6.14"
#
#
# Configuration:
#   AWS_ACCESS_KEY_ID=".."
#   AWS_SECRET_ACCESS_KEY=".."
#   HUBOT_AWS_EB_REGION=".."
#   HUBOT_GITHUB_TOKEN=".."
#
# Commands:
#   Hubot eb describe environment <name> - Get Elasticbeanstalk environment status and version
#   Hubot eb describe application <name> - Get Elasticbeanstalk application versions
#   Hubot eb describe application <name> version <version> - Get Elasticbeanstalk application version description
#   Hubot eb delete application <name> version <version> - Delete Elasticbeanstalk application version, also delete s3 file
#   Hubot eb deploy <url> to <app> <env> wiht version <version> and description <description> s3 <bucket>
#   Hubot eb deploy <githubProject> rev <revision> path <deploymentFile> to <app> <env> with version <version> and description <description> s3 <bucket>
#   Hubot eb deploy <githubProject> rev <revision> to <app> <env> with version <version> and description <description> s3 <bucket> - deploy repository archive to elastic beanstalk
#   Hubot eb deploy version <version> to <env> - deploy existed version to environment
#
#   Hubot s3 list buckets
#   Hubot s3 put <url> to <s3Bucket> as <s3Path>
#
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

  robot.respond /eb describe environment ([\w.\-\/]+)$/i, (msg) ->
    describe_env_status msg, msg.match[1]

  robot.respond /eb describe application ([\w.\-\/]+)$/i, (msg) ->
    describe_app_versions msg, msg.match[1]

  robot.respond /eb describe application ([\w.\-\/]+) version ([\w.\-\/]+)$/i, (msg) ->
    describe_app_version msg, msg.match[1], msg.match[2]

  robot.respond /eb delete application ([\w.\-\/]+) version ([\w.\-\/]+)$/i, (msg) ->
    delete_app_version msg, msg.match[1], msg.match[2]

  robot.respond(
    /eb deploy ([\w.\-\/]+) to ([\w.\-\/]+) ([\w.\-\/]+) with version ([\w.\-\/]+) and description ([\w.\-\/]+) s3 ([\w.\-\/]+)$/i,
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
    /eb deploy ([\w.\-\/]+) rev ([\w.\-\/]+) path ([\w.\-\/]+) to ([\w.\-\/]+) ([\w.\-\/]+) with version ([\w.\-\/]+) and description (.+) s3 ([\w.\-\/]+)$/i,
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

  robot.respond(
    /eb deploy ([\w.\-\/]+) rev ([\w.\-\/]+) to ([\w.\-\/]+) ([\w.\-\/]+) with version ([\w.\-\/]+) and description (.+) s3 ([\w.\-\/]+)$/i,
    (msg) ->
      repository = msg.match[1]
      branch = msg.match[2]
      app = msg.match[3]
      environment = msg.match[4]
      version = msg.match[5]
      desc = msg.match[6]
      bucket = msg.match[7]
      msg.send "Not implemented. I'm working on it..."
      # deploy_from_github_zip(
      #   msg, app, environment, version, desc, repository, branch, bucket
      # )
  )

  robot.respond /eb deploy version ([\w.\-\/]+) to ([\w.\-\/]+)$/i, (msg) ->
    version = msg.match[1]
    environment = msg.match[2]
    deploy_version msg, version, environment

  robot.respond /s3 list buckets$/i, (msg) -> s3_ls_buckets msg

  robot.respond /s3 put ([\w.\-\/:]+) to ([\w.\-\/]+) as ([\w.\-\/]+)$/i, (msg) ->
    s3_put_url msg, msg.match[1], msg.match[2], msg.match[3]


describe_env_status = (msg, environment) ->
  params =
    EnvironmentNames: [environment]
  elasticbeanstalk.describeEnvironments params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      envObj = data.Environments[0]
      if envObj
        status = envObj.Status
        version = envObj.VersionLabel
        msg.send "#{environment}'s status is #{status} with version #{version}."
      else
        msg.send "Can not find such environment."

describe_app_versions = (msg, app) ->
  params =
    ApplicationNames: [app]
  elasticbeanstalk.describeApplications params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      appObj = data.Applications[0]
      if appObj
        msg.send "#{app} has versions: #{appObj.Versions}."
      else
        msg.send "Can not find such application."

get_app_version = (msg, app, version, cb, errorCb) ->
  params =
    ApplicationName: app
    VersionLabels: [version]
  elasticbeanstalk.describeApplicationVersions params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      versionObj = data.ApplicationVersions[0]
      if versionObj
        if cb
          cb versionObj
      else
        if errorCb
          errorCb({Message: "Can not find such application and version."})
        else
          msg.send "Can not find such application and version."

delete_app_version = (msg, app, version) ->
  params =
    ApplicationName: app
    VersionLabel: version
    DeleteSourceBundle: true
  elasticbeanstalk.deleteApplicationVersion params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      msg.send "Done"

describe_app_version = (msg, app, version) ->
  get_app_version msg, app, version, (versionObj) ->
    sourceBundle = versionObj.SourceBundle
    msg.send "#{version} has description: #{versionObj.Description}."
    msg.send "Updated at #{versionObj.DateUpdated}."
    msg.send "Source bundle stores at #{sourceBundle.S3Bucket}/#{sourceBundle.S3Key}."

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
      console.log err, err.stack
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
      console.log err, err.stack
    else
      status_command = "eb describe environment #{environment}"
      msg.send "Please check the result later... use #{status_command}"

generate_s3_key = uuid.v4

deploy_from_url = (msg, app, environment, version, desc, url, bucket) ->
  s3_key = generate_s3_key()
  onVersionExist = () ->
    msg.send "I'm sorry, this version exists."
  onVersionNotExist = () ->
    s3_put_url msg, url, bucket, s3_key, (key) ->
      deploy_new_version msg, app, environment, version, desc, bucket, key
  get_app_version(
    msg, app, version, onVersionExist, onVersionNotExist, onVersionNotExist
  )

deploy_from_github = (
  msg, app, environment, version, desc, repository, branch, path, bucket) ->
  s3_key = generate_s3_key()
  onVersionExist = () ->
    msg.send "I'm sorry, this version exists."
  onVersionNotExist = () ->
    s3_put_object_from_github(
      msg, repository, branch, path, bucket, s3_key, (key) ->
        deploy_new_version msg, app, environment, version, desc, bucket, key
    )
  get_app_version(
    msg, app, version, onVersionExist, onVersionNotExist, onVersionNotExist
  )

deploy_from_github_zip = (
  msg, app, environment, version, desc, repository, branch, bucket) ->
  s3_key = generate_s3_key() + ".zip"
  onVersionExist = () ->
    msg.send "I'm sorry, this version exists."
  onVersionNotExist = () ->
    s3_put_zip_from_github(
      msg, repository, branch, bucket, s3_key, (key) ->
        deploy_new_version msg, app, environment, version, desc, bucket, key
    )
  get_app_version(
    msg, app, version, onVersionExist, onVersionNotExist, onVersionNotExist
  )


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
      console.log err, err.stack
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
      msg.send "Put object to s3! Nice work!"
      if cb
        cb()

s3_upload_stream = (msg, object, bucket, key, cb) ->
  params =
    Bucket: bucket
    Key: key
    ACL: "authenticated-read"
    Body: object
  s3.upload params, (err, data) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      msg.send "Put object to s3! Nice work!"
      if cb
        cb()

s3_put_url = (msg, url, bucket, key, cb) ->
  get_object_from_url msg, url, (body) ->
    s3_put_object msg, body, bucket, key, () ->
      if cb
        cb key

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
    s3_put_object msg, buffer, bucket, key, () ->
      if cb
        cb key

get_zip_from_github = (msg, repository, branch, cb) ->
  ghrepo = ghClient.repo repository
  ghrepo.archive 'zipball', branch, (err, data, headers) ->
    if err
      msg.send "Ooops! Error occur... #{err.message}"
      console.log err, err.stack
    else
      get_object_from_url msg, data, cb

s3_put_zip_from_github = (msg, repository, branch, bucket, key, cb) ->
  get_zip_from_github msg, repository, branch, (buffer) ->
    s3_upload_stream msg, buffer, bucket, key, () ->
      if cb
        cb key
