clone             = (obj) -> JSON.parse JSON.stringify obj

module.exports = (server, model, lib, urlprefix, parent ) ->

  @.reply_with_data = (reply,err,item,kind) ->
    reply.kind = String(kind).replace(/\//,"_") if reply.kind != "default" and kind 
    if err
      reply.code = 3 
      reply.message = err
      reply.errors.push e for e in err if typeof err is "array"
      reply.errors.push err if typeof err is "object"
    else
      reply.data = item 
    return reply

  @.register = (colname,db) ->
    me = @
    resource   = db.resources[ colname ]
    collection = db.collections[ colname ]
    collectionname = colname.replace("/","_")
    model.resources[ "/"+colname ] =
      post: clone resource.schema
    model.resources[ "/"+colname+'/all' ] =
      get: clone resource.schema
    model.resources[ "/"+colname+'/:id' ] =
      get: clone resource.schema
      del: clone resource.schema
      put: clone resource.schema

    # del and get dont need payload 
    delete model.resources[ "/"+colname+'/:id'].get.payload
    delete model.resources[ "/"+colname+'/all'].get.payload
    delete model.resources[ "/"+colname+'/:id'].del.payload

    # rest GET item
    path = '/'+colname+'/:id'
    model.resources[ path ].get.description = resource.schema.description || "retrieves a "+k+" from the database"
    model.resources[ path ].get.function =  resource.schema.function || (req, res, next, lib, reply ) ->
      me.events.emit 'onResourceCall', { method: 'get', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
        return res.send @.reply_with_data reply, err.toString(), false, colname if err
        query = db.collections[collectionname].find {id:req.params.id}
        if req.query.populate?
          fields = req.query.populate.split(',')
          query.populate field for field in fields
        query.then (items) -> 
          res.send @.reply_with_data reply, false, items, colname
        .catch (err) -> 
          return res.send @.reply_with_data reply, err, {}, "error" if err
      return false

    # rest DELETE item
    model.resources[ path ].del.description = resource.schema.description || "deletes a "+k+" from the database"
    model.resources[ path ].del.function  = resource.schema.function || (req, res, next, lib, reply ) ->
      me.events.emit 'onResourceCall', { method: 'del', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
        return res.send @.reply_with_data reply, err.toString(), false, colname if err
        db.collections[collectionname].destroy {id:req.params.id}, ( err, items) ->
          return res.send @.reply_with_data reply, err, {}, "error" if err
          res.send @.reply_with_data reply, false, items, colname
      return false

    # rest PUT item (update)
    model.resources[ path ].put.payload = resource.schema.payload 
    model.resources[ path ].put.description = resource.schema.description || "updates an existing "+k+" in the database"
    model.resources[ path ].put.function  = resource.schema.function || (req, res, next, lib, reply ) ->
      me.events.emit 'onResourceCall', { method: 'put', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
        return res.send @.reply_with_data reply, err.toString(), false, colname if err
        db.collections[collectionname].update {id:req.params.id}, req.body, ( err, items) ->
          return res.send @.reply_with_data reply, err, {}, "error" if err
          res.send @.reply_with_data reply, false, items, colname
      return false
   
    # rest GET (all)
    path = '/'+colname+'/all'
    model.resources[ path ].get.description = resource.schema.description || "retrieves a "+k+" from the database"
    model.resources[ path ].get.function =  resource.schema.function || (req, res, next, lib, reply ) ->
      me.events.emit 'onResourceCall', { method: 'get', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
        return res.send @.reply_with_data reply, err.toString(), false, colname if err
        query = db.collections[collectionname].find {}
        if req.query.populate?
          fields = req.query.populate.split(',')
          query.populate field for field in fields
        query.then (items) -> 
          res.send @.reply_with_data reply, false, items, colname
        .catch (err) -> 
          return res.send @.reply_with_data reply, err, {}, "error" if err
      return false

    # rest POST item
    path = '/'+colname
    model.resources[ path ].post.description = resource.schema.description || "inserts a "+k+" to the database"
    model.resources[ path ].post.payload = resource.schema.payload 
    model.resources[ path ].post.function = resource.schema.function || (req, res, next, lib, reply ) ->
      me.events.emit 'onResourceCall', { method: 'post', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
        return res.send @.reply_with_data reply, err.toString(), false, colname if err
        obj = db.collections[collectionname].create req.body
        .then (item) ->
          res.send @.reply_with_data reply, false, item, colname 
        .catch (err) ->
          res.send @.reply_with_data reply, err, {}, "error"
      return false 

    # special tag functions
    if colname.match(/tag$/)
      parts = colname.split('/')
      parentcolname = parts[0]

      path = '/'+colname+'/:'+parentcolname+'id/all' 
      model.resources[ path ] =
        get: clone resource.schema
      delete model.resources[ path ].get.payload
      model.resources[ path ].get.description = resource.schema.description || "tags "+k+" with :tagid"
      model.resources[ path ].get.function = resource.schema.function || (req, res, next, lib, reply ) ->
        me.events.emit 'onResourceCall', { method: 'put', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
          return res.send @.reply_with_data reply, err.toString(), false, colname if err
          db.collections[ parentcolname ].find {id:req.params[ parentcolname+'id' ]}
          .populate('tags')
          .then ( items )->
            err = parentcolname+" not found" if not items[0]?
            return res.send @.reply_with_data reply, err, {}, "error" if err
            res.send @.reply_with_data reply, false, items[0], colname
          .catch (err) -> res.send @.reply_with_data reply, err, false, colname
        return false 

      path = '/'+colname+'/:'+parentcolname+'id/:tagid/enable'
      model.resources[ path ] =
        get: clone resource.schema
      delete model.resources[ path ].get.payload
      model.resources[ path ].get.description = resource.schema.description || "tags "+k+" with :tagid"
      model.resources[ path ].get.function = resource.schema.function || (req, res, next, lib, reply ) ->
        me.events.emit 'onResourceCall', { method: 'put', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
          return res.send @.reply_with_data reply, err.toString(), false, colname if err
          db.collections[ parentcolname ].find {id:req.params[ parentcolname+'id' ]}
          .populate('tags')
          .then ( items )->
            err = parentcolname+" not found" if not items[0]?
            return res.send @.reply_with_data reply, err, {}, "error" if err
            items[0].tags.add req.params.tagid
            items[0].save()
            reply.message = "added tagid "+req.params.tagid
            res.send @.reply_with_data reply, false, {}, colname
          .catch (err) -> res.send @.reply_with_data reply, err, false, colname
        return false 

      path = '/'+colname+'/:'+parts[0]+'id/:tagid/disable'
      model.resources[ path ] =
        get: clone resource.schema
      delete model.resources[ path ].get.payload
      model.resources[ path ].get.description = resource.schema.description || "tags "+k+" with :tagid"
      model.resources[ path ].get.function = resource.schema.function || (req, res, next, lib, reply ) ->
        me.events.emit 'onResourceCall', { method: 'put', path: path, req: req, res: res, lib: lib, reply: reply, emitter: parent }, (err) ->
          return res.send @.reply_with_data reply, err.toString(), false, colname if err
          db.collections[ parentcolname ].find {id:req.params[ parentcolname+'id' ]}
          .populate('tags')
          .then ( items )->
            err = parentcolname+" not found" if not items[0]?
            return res.send @.reply_with_data reply, err, {}, "error" if err
            items[0].tags.remove req.params.tagid
            items[0].save()
            reply.message = "removed tagid "+req.params.tagid
            res.send @.reply_with_data reply, false, {}, colname
          .catch (err) -> res.send @.reply_with_data reply, err, false, colname
        return false 
  
  return @

