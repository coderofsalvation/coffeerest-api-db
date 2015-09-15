Schema = require("jugglingdb").Schema
clone = (obj) -> JSON.parse JSON.stringify obj

module.exports = (server, model, lib, urlprefix ) ->

  @.authenticate = () -> return true

  @.reply_with_data = (reply,err,item,kind) ->
    reply.kind = kind
    if err
      reply.code = 3 
      reply.message = err
      reply.errors.push e for e in err if typeof err is "array"
      reply.errors.push err if typeof err is "object"
    else
      reply.data = item 
    return reply

  @.jsonschema2jugglingschema = (jsonschema) ->
    js = clone jsonschema
    for k,v of js.schema.payload
      js[k] = {}
      js[k].default = Date.now if v.default? and v.default is "Date.now"
      js[k].index = v.index if v.index? 
      if v.type? 
        switch
          when v.type is "string"
            if js.typehint? and js.typehint is "content"
              js[k].type = Schema.text 
            if js.typehint? and js.typehint is "date"
              js[k].type = Date 
            else
              js[k].type = String 
              js[k].length = 255
          when v.type is "boolean"
            js[k].type = Boolean
          when v.type is "object" or "array"
            js[k].type = Schema.JSON 
          when v.type is "integer" or "number"
            js[k].type = Number
    delete js.schema
    return js 

  @.dbtype = model.db.type
  require 'jugglingdb-'+model.db.type
  schema = new Schema model.db.type, model.db.config 
  @.collections = {}
     
  @.registerRest = (colname,collection,collections) ->
    me = @
    collectionname = colname.replace("/","_")
    model.resources[ "/"+colname ] =
      post: clone collection.resource.schema
    model.resources[ "/"+colname+'/:id' ] =
      get: clone collection.resource.schema
      del: clone collection.resource.schema
      put: clone collection.resource.schema

    # del and get dont need payload 
    delete model.resources[ "/"+colname+'/:id'].get.payload
    delete model.resources[ "/"+colname+'/:id'].del.payload

    model.resources[ "/"+colname+'/:id'].get.description = collection.resource.schema.description || "retrieves a "+k+" from the database"
    model.resources[ "/"+colname+'/:id'].get.function =  collection.resource.schema.function || (req, res, next, lib, reply ) ->
      obj = collection.jugglingdb
      obj.all {where:{ id: req.params.id}}, (err,item) ->
        if err
          res.send @.reply_with_data reply, err, item, colname if err
        else 
          res.send @.reply_with_data reply, err, item[0], colname
        next()
      return false

    model.resources[ '/'+colname+'/:id' ].del.description = collection.resource.schema.description || "deletes a "+k+" from the database"
    model.resources[ '/'+colname+'/:id' ].del.function  = collection.resource.schema.function || (req, res, next, lib, reply ) ->
      obj = collection.jugglingdb
      obj.all {where:{ id: req.params.id}}, (err,item) ->
        if err 
          res.send @.reply_with_data reply, err, item, colname if err
        else
        item[0].destroy (err) ->
          reply.message = "deleted succesfully" if not err
          res.send @.reply_with_data reply, err, {}, colname
        next()
      return false

    model.resources[ "/"+colname ].post.description = collection.resource.schema.description || "inserts a "+k+" to the database"
    model.resources[ "/"+colname ].post.payload = collection.resource.schema.payload 
    model.resources[ "/"+colname ].post.function = collection.resource.schema.function || (req, res, next, lib, reply ) ->
      obj = new collection.jugglingdb()
      obj[k] = v for k,v of req.body
      obj.save (err,item) ->
        reply.kind = collectionname 
        res.send @.reply_with_data reply, err, item
        next()
      return false 

    model.resources[ '/'+colname+'/:id' ].put.payload = collection.resource.schema.payload 
    model.resources[ '/'+colname+'/:id' ].put.description = collection.resource.schema.description || "updates an existing "+k+" in the database"
    model.resources[ '/'+colname+'/:id' ].put.function  = collection.resource.schema.function || (req, res, next, lib, reply ) ->
      obj = new collection.jugglingdb()
      req.body.id = req.params.id
      obj[k] = v for k,v of req.body
      obj.save (err,item) ->
        res.send @.reply_with_data reply, err, item, colname
        next()
      return false

  # define models 
  for collectionname,resource of model.db.resources 
    s = jsonschema2jugglingschema resource
    collection = {}; (collection[k] = v if k not in ["hasMany","belongsTo"]) for k,v of s
    console.log "creating db collection: "+collectionname
    @.collections[collectionname] =
      resource: resource 
      jugglingdb: schema.define( collectionname, collection )

  # define relations
  for collectionname,resource of model.db.resources 
    for k,v of resource
      if k in ["hasMany","belongsTo"]
        for collection,as of v 
          console.log "creating db collection relation: "+collectionname+" -> "+collection 
          @.collections[collectionname].jugglingdb[k]( @.collections[collection].jugglingdb, as )


  # setup rest api-endpoints
  for k,collection of @.collections 
    ( (colname,collection,collections) ->
      model.replyschema.payload.kind.enum.push colname
      registerRest colname, collection, collections
      if collection.resource.schema.taggable?
        tagcolname = colname+"/tag"
        resource  =
          schema:
            authenticate: true
            description: colname+" tags "
            payload:
              name:      { type: "string",  required:true, default: "is user" }
              permissions: 
                type: "array"
                default: [{
                  resource: "/user/:id"
                  method: "get"
                  fields: ["update user email"]
                }]
                items: [{
                  type: "object"
                  properties: 
                    resource: { type: "string", default: "/article/:id" }
                    method: { type: "string", enum:["get","del","post","put"], default: "get" }
                    fields:
                      type: "array"
                      item: [{ type: "string" }]
                }]
        ts = jsonschema2jugglingschema resource
        tagcollection = {}; (tagcollection[kk] = vv if kk not in ["hasMany","belongsTo"]) for kk,vv of ts
        collections[ colname+"_tag" ] = 
          resource: resource
          jugglingdb: schema.define( colname+"_tag", tagcollection )
        registerRest tagcolname, collections[ colname+"_tag" ], collections
        collection.jugglingdb.hasMany collections[ colname+"_tag" ].jugglingdb, { as: 'tags',  foreignKey: 'tag_id' }
        collections[ colname+"_tag" ].jugglingdb.belongsTo collection.jugglingdb, { as: colname+'s', foreignKey: 'tag_id' }
    )(k,collection,@.collections)

  console.log "TODO: dbrelations + jsonform2api"

  lib.coffeerest = {} if not lib.coffeerest?
  lib.coffeerest.db = @

  ###
  # define any custom method 
  User::getNameAndAge = ->
    @name + ', ' + @age
  # setup relationships 
  User.hasMany(Post,   {as: 'posts',  foreignKey: 'userId'})
  # creates instance methods: 
  # user.posts(conds) 
  # user.posts.build(data) # like new Post({userId: user.id}); 
  # user.posts.create(data) # build and save 
 
  Post.belongsTo(User, {as: 'author', foreignKey: 'userId'})
  # creates instance methods: 
  # post.author(callback) -- getter when called with function 
  # post.author() -- sync getter when called without params 
  # post.author(user) -- setter when called with object 
  
  User.hasAndBelongsToMany('groups')
  # user.groups(callback) - get groups of user 
  # user.groups.create(data, callback) - create new group and connect with user 
  # user.groups.add(group, callback) - connect existing group with user 
  # user.groups.remove(group, callback) - remove connection between group and user 
  ###
