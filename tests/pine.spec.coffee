_ = require('lodash')
m = require('mochainon')
Promise = require('bluebird')
url = require('url')
tokens = require('./fixtures/tokens.json')
getToken = require('resin-token')
getPine = require('../lib/pine')

IS_BROWSER = window?

dataDirectory = null
apiUrl = 'https://api.resin.io'
if IS_BROWSER
	# The browser mock assumes global fetch prototypes exist
	# Can improve after https://github.com/wheresrhys/fetch-mock/issues/158
	realFetchModule = require('fetch-ponyfill')({ Promise })
	_.assign(global, _.pick(realFetchModule, 'Headers', 'Request', 'Response'))
else
	temp = require('temp').track()
	dataDirectory = temp.mkdirSync()

fetchMock = require('fetch-mock').sandbox(Promise)
# Promise sandbox config needs a little help. See:
# https://github.com/wheresrhys/fetch-mock/issues/159#issuecomment-268249788
fetchMock.fetchMock.Promise = Promise
require('resin-request/build/utils').fetch = fetchMock.fetchMock # Can become just fetchMock after issue above is fixed.

token = getToken({ dataDirectory })
request = require('resin-request')({ dataDirectory })

apiVersion = 'v2'

buildPineInstance = (extraOpts) ->
	getPine _.assign {
		apiUrl, apiVersion, request, token
		apiKey: null
	}, extraOpts

describe 'Pine:', ->

	describe '.apiPrefix', ->

		it "should equal /#{apiVersion}/", ->
			pine = buildPineInstance()
			m.chai.expect(pine.apiPrefix).to.equal(pine.API_PREFIX)

	# The intention of this spec is to quickly double check
	# the internal _request() method works as expected.
	# The nitty grits of request are tested in resin-request.

	describe 'given a /whoami endpoint', ->

		beforeEach ->
			@pine = buildPineInstance()
			fetchMock.get("#{@pine.API_URL}/whoami", tokens.johndoe.token)

		afterEach ->
			fetchMock.restore()

		describe '._request()', ->

			describe 'given there is no token', ->

				beforeEach ->
					token.remove()

				describe 'given a simple GET endpoint', ->

					beforeEach ->
						@pine = buildPineInstance()
						fetchMock.get "begin:#{@pine.API_URL}/foo",
							body: hello: 'world'
							headers:
								'Content-Type': 'application/json'

					afterEach ->
						fetchMock.restore()

					describe 'given there is no api key', ->
						beforeEach: ->
							@pine = buildPineInstance(apiKey: '')

						it 'should be rejected with an authentication error message', ->
							promise = @pine._request
								baseUrl: @pine.API_URL
								method: 'GET'
								url: '/foo'
							m.chai.expect(promise).to.be.rejectedWith('You have to log in')

					describe 'given there is an api key', ->
						beforeEach ->
							@pine = buildPineInstance(apiKey: '123456789')

						it 'should make the request successfully', ->
							promise = @pine._request
								baseUrl: @pine.API_URL
								method: 'GET'
								url: '/foo'
							m.chai.expect(promise).to.become(hello: 'world')

			describe 'given there is a token', ->

				beforeEach ->
					token.set(tokens.johndoe.token)

				describe 'given a simple GET endpoint', ->

					beforeEach ->
						@pine = buildPineInstance()
						fetchMock.get "#{@pine.API_URL}/foo",
							body: hello: 'world'
							headers:
								'Content-Type': 'application/json'

					afterEach ->
						fetchMock.restore()

					it 'should eventually become the response body', ->
						promise = @pine._request
							baseUrl: @pine.API_URL
							method: 'GET'
							url: '/foo'
						m.chai.expect(promise).to.eventually.become(hello: 'world')

				describe 'given a POST endpoint that mirrors the request body', ->

					beforeEach ->
						@pine = buildPineInstance()
						fetchMock.post "#{@pine.API_URL}/foo", (url, opts) ->
							status: 200
							body: opts.body
							headers:
								'Content-Type': 'application/json'

					afterEach ->
						fetchMock.restore()

					it 'should eventually become the body', ->
						promise = @pine._request
							baseUrl: @pine.API_URL
							method: 'POST'
							url: '/foo'
							body:
								foo: 'bar'
						m.chai.expect(promise).to.eventually.become(foo: 'bar')

				describe '.get()', ->

					describe 'given a working pine endpoint', ->

						beforeEach ->
							@pine = buildPineInstance()

							@applications =
								d: [
									{ id: 1, app_name: 'Bar' }
									{ id: 2, app_name: 'Foo' }
								]

							fetchMock.get "#{@pine.API_URL}/#{apiVersion}/application?$orderby=app_name asc",
								status: 200
								body: @applications
								headers:
									'Content-Type': 'application/json'

						afterEach ->
							fetchMock.restore()

						it 'should make the correct request', ->
							promise = @pine.get
								resource: 'application'
								options:
									orderby: 'app_name asc'
							m.chai.expect(promise).to.eventually.become(@applications.d)

					describe 'given an endpoint that returns an error', ->

						beforeEach ->
							@pine = buildPineInstance()
							fetchMock.get "#{@pine.API_URL}/#{apiVersion}/application",
								status: 500
								body: 'Internal Server Error'

						afterEach ->
							fetchMock.restore()

						it 'should reject the promise with an error message', ->
							promise = @pine.get
								resource: 'application'

							m.chai.expect(promise).to.be.rejectedWith('Internal Server Error')

				describe '.post()', ->

					describe 'given a working pine endpoint that gives back the request body', ->

						beforeEach ->
							@pine = buildPineInstance()
							fetchMock.post "#{@pine.API_URL}/#{apiVersion}/application", (url, opts) ->
								status: 201
								body: opts.body
								headers:
									'Content-Type': 'application/json'

						afterEach ->
							fetchMock.restore()

						it 'should get back the body', ->
							promise = @pine.post
								resource: 'application'
								body:
									app_name: 'App1'
									device_type: 'raspberry-pi'

							m.chai.expect(promise).to.eventually.become
								app_name: 'App1'
								device_type: 'raspberry-pi'

					describe 'given pine endpoint that returns an error', ->

						beforeEach ->
							@pine = buildPineInstance()
							fetchMock.post "#{@pine.API_URL}/#{apiVersion}/application",
								status: 404
								body: 'Unsupported device type'

						afterEach ->
							fetchMock.restore()

						it 'should reject the promise with an error message', ->
							promise = @pine.post
								resource: 'application'
								body:
									app_name: 'App1'

							m.chai.expect(promise).to.be.rejectedWith('Unsupported device type')
