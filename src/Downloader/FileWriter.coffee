module.exports = (Promise, fs, path, crypto)->
    class CynnyFileWriter

        _finalized: null

        _file: null
        _tempFile: null

        _ws: null

        _hashType: null
        _hash: null
        _hashValue: null

        constructor: (@_file, @_hashType='md5')->
            @_tempFile = "#{path.dirname(@_file)}/.#{path.basename(@_file)}"
            @_ws = fs.createWriteStream(@_tempFile, {flags: 'wx'})

            @_hashType = if @_hash then crypto.createHash(@_hashType) else false

            @_finalized = false

        write: (data)->
            @_ws.write data, ()=>
                data = null
            @_hash.update(data) if @_hash
            return true

        getChecksum: ()->
            throw new Error("Writestream has not been finalized yet") unless @_finalized
            throw new Error("Hashing disabled") unless @_hash

            return @_hashValue

        finalize: ()->
            return @_closeStream().then(@_finishHash.bind(@)).then(@_moveFile.bind(@))

        _closeStream: ()->
            return new Promise (resolve, reject)=>
                @_ws.once 'finish', ()=>
                    @_ws = null
                    fs.rename @_tempFile, @_file, (err)=>
                        @_finalized = true
                        if err then reject(err) else resolve()
                @_ws.end()

        _finishHash: ()->
            @_hashValue = @_hash.digest('hex') if @_hash
            return true

        _moveFile: ()->
            return new Promise (resolve, reject)=>
                fs.rename @_tempFile, @_file, (err)=>
                    if err then reject(err) else resolve()
