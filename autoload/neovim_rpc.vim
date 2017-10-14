

if has('pythonx')
	let s:py = 'pythonx'
	let s:pyeval = function('pyxeval')
elseif has('python3')
	let s:py = 'python3'
	let s:pyeval = function('py3eval')
else
	let s:py = 'python'
	let s:pyeval = function('pyeval')
endif

func! neovim_rpc#serveraddr()
	if exists('g:_neovim_rpc_nvim_server')
		return g:_neovim_rpc_nvim_server
	endif

	execute s:py ' import neovim_rpc_server'
	let l:servers = s:pyeval('neovim_rpc_server.start()')

	let g:_neovim_rpc_nvim_server     = l:servers[0]
	let g:_neovim_rpc_vim_server = l:servers[1]

	let g:_neovim_rpc_main_channel = ch_open(g:_neovim_rpc_vim_server)

	" close channel before vim exit
	" au VimLeavePre *  let s:leaving = 1 | execute s:py . ' neovim_rpc_server.stop()'

	" identify myself
	call ch_sendexpr(g:_neovim_rpc_main_channel,'neovim_rpc_setup')

	return g:_neovim_rpc_nvim_server
endfunc

" elegant python function call wrapper
func! neovim_rpc#pyxcall(func,...)
	execute s:py . ' import vim'
	execute s:py . ' import json'
	let l:i = 1
	let l:cnt = len(a:000)
	let l:args = []
	while l:i <= l:cnt
		call add(l:args,'json.loads(vim.eval("json_encode(a:'.l:i.')"))')
		let l:i += 1
	endwhile
	return s:pyeval(a:func . '(' . join(l:args,',') . ')')
	" return l:args
endfunc

" supported opt keys:
" - on_stdout
" - on_stderr
" - on_exit
" - detach
func! neovim_rpc#jobstart(cmd,...)

	let l:opts = {}
	if len(a:000)
		let l:opts = a:1
	endif

	let l:real_opts = {'mode': 'raw'}
	if has_key(l:opts,'detach') && l:opts['detach']
		let l:real_opts['stoponexit'] = ''
	endif

	if has_key(l:opts,'on_stdout')
		let l:real_opts['out_cb'] = function('neovim_rpc#_on_stdout')
	endif
	if has_key(l:opts,'on_stderr')
		let l:real_opts['err_cb'] = function('neovim_rpc#_on_stderr')
	endif
	if has_key(l:opts,'on_exit')
		let l:real_opts['exit_cb'] = function('neovim_rpc#_on_exit')
	endif

	let l:job   = job_start(a:cmd, l:real_opts)
	let l:jobid = ch_info(l:job)['id']

	let g:_neovim_rpc_jobs[l:jobid] = {'cmd':a:cmd, 'opts': l:opts, 'job': l:job}

	return l:jobid
endfunc

func! neovim_rpc#jobstop(jobid)
	let l:job = g:_neovim_rpc_jobs[a:jobid]['job']
	return job_stop(l:job)
endfunc

func! neovim_rpc#rpcnotify(channel,event,...)
	call neovim_rpc#pyxcall('neovim_rpc_server.rpcnotify',a:channel,a:event,a:000)
endfunc

let s:rspid = 1
func! neovim_rpc#rpcrequest(channel, event, ...)
    let s:rspid = s:rspid + 1
    " a unique key for storing response
    let rspid = '' . s:rspid
    call ch_evalexpr(g:_neovim_rpc_main_channel, ['rpcrequest', a:channel, a:event, a:000, rspid])
	execute s:py ' import neovim_rpc_server, json'
    let [err, result] = json_decode(s:pyeval('json.dumps(neovim_rpc_server.responses["' . rspid . '"])'))
    execute s:py 'neovim_rpc_server.responses.pop("' . rspid . '")'
    if err
        if type(err) == type('')
            throw err
        endif
        throw err[1]
    endif
    return result
endfunc

func! neovim_rpc#_on_stdout(job,data)
	let l:jobid = ch_info(a:job)['id']
	let l:opts = g:_neovim_rpc_jobs[l:jobid]['opts']
	" convert to neovim style function call
	call call(l:opts['on_stdout'],[l:jobid,split(a:data,"\n",1),'stdout'],l:opts)
endfunc

func! neovim_rpc#_on_stderr(job,data)
	let l:jobid = ch_info(a:job)['id']
	let l:opts = g:_neovim_rpc_jobs[l:jobid]['opts']
	" convert to neovim style function call
	call call(l:opts['on_stderr'],[l:jobid,split(a:data,"\n",1),'stderr'],l:opts)
endfunc

func! neovim_rpc#_on_exit(job,status)
	let l:jobid = ch_info(a:job)['id']
	let l:opts = g:_neovim_rpc_jobs[l:jobid]['opts']
	" convert to neovim style function call
	call call(l:opts['on_exit'],[l:jobid,a:status,'exit'],l:opts)
	unlet g:_neovim_rpc_jobs[l:jobid]
endfunc

func! neovim_rpc#_callback()
	execute s:py . ' neovim_rpc_server.process_pending_requests()'
endfunc

let g:_neovim_rpc_main_channel = -1
let g:_neovim_rpc_jobs = {}

let s:leaving = 0
