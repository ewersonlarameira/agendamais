import {guard,failure,rpcNamed} from '../../../lib/agenda';
export async function POST(req:Request){try{guard(req);const {op,p={}}=await req.json() as any;if(!['status','register','unregister','test'].includes(op))throw new Error('Operação inválida.');return Response.json(await rpcNamed('agenda_push_client',{op,p}),{headers:{'Cache-Control':'no-store'}});}catch(e){return failure(e)}}
