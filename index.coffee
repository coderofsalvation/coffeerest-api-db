Schema = require("jugglingdb").Schema

module.exports = (server, model, lib, urlprefix ) ->

  @.reply_with_data = (reply,err,item,kind) ->
    reply.kind = kind
    if err
      reply.code = 3 
      reply.message err
    else
      reply.data = item 
    return reply

  @.jsonschema2jugglingschema = (jsonschema) ->
    js = JSON.parse( JSON.stringify jsonschema )
    for k,v of js.schema.properties
      v.default = Date.now if v.default? and v.default is "Date.now"
      if v.type? 
        js[k] = {}
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
          when v.type is "integer" or "number"
            js[k].type = Number
    delete js.schema
    return js 

  @.dbtype = model.db.type
  require 'jugglingdb-'+model.db.type
  schema = new Schema model.db.type, model.db.config 
  collections = {}
     
  @.registerRest = (colname,collection,collections) ->
    model.resources[ "/"+colname ] = 
      post:
        description: collection.resource.schema.description || "inserts a "+k+" to the database"
        payload: collection.resource.schema.properties
        function: collection.resource.schema.function || (req, res, next, lib, reply ) ->
          obj = new collections[colname].jugglingdb()
          obj[k] = v for k,v of req.body
          obj.save (err,item) ->
            reply.kind = colname
            res.send @.reply_with_data reply, err, item
            next()
          return false 

    model.resources[ "/"+colname+'/:id' ] =
      get:
        description: collection.resource.schema.description || "retrieves a "+k+" from the database"
        function: collection.resource.schema.function || (req, res, next, lib, reply ) ->
          obj = collections[colname].jugglingdb
          obj.all {where:{ id: req.params.id}}, (err,item) ->
            if err
              res.send @.reply_with_data reply, err, item, colname if err
            else 
              res.send @.reply_with_data reply, err, item[0], colname
            next()
          return false
      del:
        description: collection.resource.schema.description || "deletes a "+k+" from the database"
        function: collection.resource.schema.function || (req, res, next, lib, reply ) ->
          obj = collections[colname].jugglingdb
          obj.all {where:{ id: req.params.id}}, (err,item) ->
            console.log err 
            console.dir item[0]
            if err 
              res.send @.reply_with_data reply, err, item, colname if err
            else
            item[0].destroy (err) ->
              reply.message = "deleted succesfully" if not err
              res.send @.reply_with_data reply, err, {}, colname
            next()
          return false
      put:
        payload: collection.resource.schema.properties
        description: collection.resource.schema.description || "updates an existing "+k+" in the database"
        function: collection.resource.schema.function || (req, res, next, lib, reply ) ->
          console.log colname+":"+req.params.id 
          obj = collections[colname].jugglingdb
          obj.all {where:{ id: req.params.id}}, (err,item) ->
            if err
              res.send @.reply_with_data reply, err, item, colname
            else
              item[0][k] = v for k,v of req.body 
              item[0].save (err,item) ->
                res.send @.reply_with_data reply, err, item[0], colname
            next()
          return false

  # define models 
  for collectionname,resource of model.db.resources 
    s = jsonschema2jugglingschema resource
    collection = {}; (collection[k] = v if k not in ["hasMany","belongsTo"]) for k,v of s
    console.log "creating db collection: "+collectionname
    collections[collectionname] =
      resource: resource 
      jugglingdb: schema.define( collectionname, collection )

  # define relations
  for collectionname,resource of model.db.resources 
    for k,v of resource
      if k in ["hasMany","belongsTo"]
        for collection,as of v 
          console.log "creating db collection relation: "+collectionname+" -> "+collection 
          collections[collectionname].jugglingdb[k]( collections[collection].jugglingdb, as )


  # setup rest api-endpoints
  for k,collection of collections 
    ( (colname,collection,collections) ->
      model.replyschema.properties.kind.enum.push colname
      registerRest colname, collection, collections
      if collection.resource.schema.taggable
        colname += "/tags"
        registerRest colname, collection, collections
    )(k,collection,collections)
  console.log "TODO: dbrelations + acl + customtags/attributes + jsonform2api"
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
