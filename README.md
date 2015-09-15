Unfancy rest apis, connect any db (redis/mysql/mongodb/etc) to coffeerest

<img alt="" src="https://github.com/coderofsalvation/coffeerest-api/raw/master/coffeerest.png" width="20%" />

Connect any database to coffeerest-api

## Ouch! Is it that simple?

Just add these fields to your coffeerest-api `model.coffee` specification 

    module.exports = 
      name: "project foo"
      db: 
        type: "redis"
        config:
          port: 6379
        resources:
          article:
            schema:
              taggable: true
              description: "this foo bar"
              properties:
                id:
                  type: "integer"
                title: 
                  type: "string"
                  length: 255
                  default: "title not set"
                  required: true
                  index: true
                content:
                  type: "string"
                  default: "Lorem ipsum"
                  typehint: "content"
                  required: true
                date:
                  type: "string"
                  typehint: "date"
                  default: "Date.now"
            belongsTo:
              user:      { as: 'user', foreignKey: 'user_id' }
          user:
            schema:
              taggable: true
              description: "author"
              properties:
                id:      { type: "integer", default: 123, requiretag: ["admin"] }
                email:   { type: "string", required:true, default: 'John Doe', requiretag: ["admin"] }
                apikey:  { type: "string",  required: true, default: "john@doe.com", pattern: "/\S+@\S+\.\S+/" }
            hasMany:
              article: { as: 'articles', foreignKey: 'user_id' }
      resources:
        '/book/:category':
          post:
            ...

## Usage 

    npm install coffeerest-api
    npm install coffeerest-api-db

for more info / servercode see [coffeerest-api](https://www.npmjs.com/package/coffeerest-api)

## Example 


    $ coffee server.coffee &
    registering REST resource: /v1/article (post)
    registering REST resource: /v1/article/:id (get)
    registering REST resource: /v1/article/:id (del)
    registering REST resource: /v1/article/:id (put)
    registering REST resource: /v1/article/tags (post)
    registering REST resource: /v1/article/tags/:id (get)
    registering REST resource: /v1/article/tags/:id (del)
    registering REST resource: /v1/article/tags/:id (put)
    registering REST resource: /v1/user (post)
    registering REST resource: /v1/user/:id (get)
    registering REST resource: /v1/user/:id (del)
    registering REST resource: /v1/user/:id (put)
    registering REST resource: /v1/user/tags (post)
    registering REST resource: /v1/user/tags/:id (get)
    registering REST resource: /v1/user/tags/:id (del)
    registering REST resource: /v1/user/tags/:id (put)
    $ curl -H 'Content-Type: application/json' -X POST http://localhost:$PORT/v1/article --data '{"title":"foo","content":"bar"}' 
    $ curl -H 'Content-Type: application/json' http://localhost:$PORT/v1/article/1 
    $ curl -H 'Content-Type: application/json' -X PUT http://localhost:$PORT/v1/article/1 --data '{"title":"flopje", "content":"bar"}' 
    $ curl -H 'Content-Type: application/json' http://localhost:$PORT/v1/article/1 
    $ curl -H 'Content-Type: application/json' -X DELETE http://localhost:$PORT/v1/article/1 

Voila! all api-endpoints are generated, validated and connected to a database store of your choice (using jugglingdb)!

## Tag system 

coffeerest-api-db also includes a tag/permission system.
What is that?
Well..this was inspired by roundup tracker.
It allows tagging database-objects and adding permissions to tags.
The aim is to offer extendability to a databasedesign without fiddling with code.
For example, many 'could you add this extra field in the database'-featurerequest or 'hey we need an extra category'-featurerequest could be prevented by just having tag-features. 

*need more docs here*
