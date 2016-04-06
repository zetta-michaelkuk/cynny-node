module.exports = (Promise, EventEmitter, request, crypto, async, CynnyFileWriter)->
    class CynnyDownloader extends EventEmitter

        _storageUrl: null
        _object: null
        _bucket: null

        _file: null

        _signedToken: null
        _downloadToken: null

        _expectedMd5: null
        _verifyChecksum: null

        _totalChunks: null
        _currentChunk: null

        _fileInstance: null

        _lastProgress: null

        constructor: (params={})->
            super()

            required = ['storageUrl', 'object', 'bucket', 'file', 'signedToken', 'downloadToken']
            @_processParams(params, required)

            @_streamMd5 = crypto.createHash('md5').setEncoding('hex')

            @_hiddenFile = "#{path.dirname(@_file)}/.#{path.basename(@_file)}"
            @_verifyChecksum: if params.hasOwnProperty('verifyChecksum') then params.verifyChecksum else false

        _processParams: (params, required)->
            keys = Object.keys(params)

            for k in required
                throw new Error("Parameter '#{k}' is required but missing") if keys.indexOf(k) == -1
                @["_#{k}"] = params[k]

            return

        download: ()->
            @_currentChunk = 0
            return @_getObjectInfo().then(@_performDownload.bind(@)).then(@_finalizeFile.bind(@)).then(@_verifyChecksum.bind(@))

        _getObjectInfo: ()->
            return new Promise (resolve, reject)=>
                requestOptions =
                    uri: "#{@_storageUrl}/b/#{@_bucket}/o/#{@_object}"
                    headers:
                        'x-cyn-signedtoken': @_signedToken

                request.get requestOptions, (err, response, body)=>
                    return reject(err) if err

                    data = if typeof body == 'string' then JSON.parse(body).data else body.data

                    @_downloadToken = data.downloadToken
                    @_expectedMd5 = data.md5Encoding
                    @_totalChunks = Math.ceil(data.size / data.chunkSize)

        _progress: ()->
            currentProgress = Math.floor(@_currentChunk / @_totalChunks * 100)
            @emit('progress', currentProgress) if @_lastProgress != currentProgress
            @_lastProgress = currentProgress

        _performDownload: ()->
            return new Promise (resolve, reject)=>
                criteria = ()=>
                    return @_currentChunk < @_totalChunks

                iterator: (cb)=>
                    requestOptions =
                        uri: "#{@_storageUrl}/b/#{@_bucket}/o/#{@_object}/cnk/#{@_currentChunk}"
                        headers:
                            'x-cyn-signedtoken': @_signedToken
                            'x-cyn-downloadtoken': @_downloadToken

                    request.get requestOptions, (err, response, body)=>
                        # TODO: Implement download retries in the future
                        @_currentChunk += 1
                        @_progress()
                        if err || response.statusCode != 200
                            return cb(err || response.statusCode)
                        else
                            @_fileInstance.write(body)
                            cb()

                callback: (err)=>
                    if err then return reject(err) else resolve()

        _finalizeFile: ()->
            return @_fileInstance.finalize()

        _verifyChecksum: ()->
            throw new Error("Checksum mismatch") if @_expectedMd5 != @_fileInstance.getChecksum()
            return true
