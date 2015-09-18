clone             = (obj) -> JSON.parse JSON.stringify obj
Waterline         = require('waterline')
asyncEventEmitter = require('async-eventemitter');
 
module.exports = (server, model, lib, urlprefix ) ->

  me = @
  @.rest        = require('./src/rest.coffee')(server,model,lib,urlprefix,@)
  @.orm         = new Waterline()
  @.collections = {}
  @.resources   = {}
  @.connections = {}

  # synchronous event handler
  @.events      = new asyncEventEmitter()

  # utility to convert jsonschema rest resource to waterline schema
  @.jsonschema2dbschema = (jsonschema,collectionname) ->
    jsonschema.identity = collectionname
    jsonschema.attributes = clone jsonschema.schema.payload 
    allowed = ["type","minLength","maxLength","index"]
    if jsonschema.schema.owner?
      jsonschema.attributes.owner = { model: jsonschema.schema.owner }
    for k,v of jsonschema.attributes 
      js = jsonschema.attributes
      if v.type? 
        switch
          when v.type is "object" or "array"
            js[k].type = "json"
      for property,value of v
        if property not in allowed
          delete js[k] 
    delete jsonschema.schema
    return jsonschema 

  @.addHooks = (schema, collectionnname, collections) ->
    for event in ["afterInitialize","beforeCreate","afterCreate","beforeSave","afterSave","beforeUpdate","afterUpdate","beforeDestroy","afterDestroy","beforeValidate","afterValidate"]
      schema[event] = ( (event,collectionname,collections) ->
        (data,next) -> 
          me.events.emit event, {collectionname: collectionname, collections:collections, data:data }, next
      )(event, collectionname, collections)

  # utility to get collectionname from url 
  @.url_to_resourcecollection = (path) ->
    pathparts = path.split('/')
    cn = pathparts[1]
    { collection: @.collections[cn], resource: @.resources[cn] }

  # init db
  model.db.config.adapters = {}
  for name,connection of model.db.config.connections
    model.db.config.adapters[ connection.adapter ] = require 'sails-'+connection.adapter


  # define models 
  for collectionname,resource of model.db.resources 
    resource.schema.payload.tags_ids = { type: "array", items: [{type:"integer"}], description: 'array of tag ids which belong to user',default: [1,3]} if resource.schema.taggable?
    s = jsonschema2dbschema clone(resource), collectionname
    if resource.schema.taggable?
      s.attributes.tags =
        collection: collectionname+"_tag"
        via: collectionname+'s',
        dominant: true
      s.attributes.tags_flatten = () ->
        arr = {}; for tag in @.tags
          arr[tag.name] = true 
          (arr[subtag] = true for subtag in tag.subtags) if tag.subtags?
        return arr
    @.addHooks s, collectionname, @.collections
    collection = Waterline.Collection.extend(s)
    console.log "creating db collection: "+collectionname
    @.collections[collectionname] = collection 
    @.resources[collectionname] = resource
    @.orm.loadCollection( collection )

  # setup rest api-endpoints
  for k,collection of @.collections 
    ( (colname,collection,collections) ->
      model.replyschema.payload.kind.enum.push colname
      resource = @.resources[ colname ]
      @.rest.register colname, @
      if resource.schema.taggable?
        tagcolname = colname+"/tag"
        resource  =
          connection: 'default'
          schema:
            authenticate: true
            description: colname+" tags "
            required: ['name']
            payload:
              name:      { type: "string", default: "is user" }
              subtags: 
                type: "array"
                items: [{ type: "string" }]
                default: ["can create,read,update user email"]
        ts = jsonschema2dbschema clone(resource), colname+"_tag"
        ts.attributes[colname+'s'] =
          collection: colname 
          via: 'tags'
        @.addHooks ts,collectionname, @.collections
        collection = Waterline.Collection.extend(ts)
        @.collections[ colname+"_tag" ] = collection 
        @.resources[ tagcolname ] = resource
        @.orm.loadCollection( collection )
        @.rest.register tagcolname, @ 
    )(k,collection,@.collections)

  console.log "TODO: dbrelations + jsonform2api"

  # start the database 
  @.orm.initialize model.db.config, (err, models) ->
    console.error err if err
    me.collections = models.collections 
    me.connections = models.connections
    console.log "database(s) started"

  return @
