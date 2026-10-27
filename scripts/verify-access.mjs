// Read the Sites service-access token from stdin. Never log it or write it to disk.
let input=''; for await (const chunk of process.stdin) input+=chunk;
const {origin,serviceToken}=JSON.parse(input);
const baseHeaders={'OAI-Sites-Authorization':'Bearer '+serviceToken};
const tests=[
 {path:'/api/auth',check:(r,d)=>r.status===200&&d.isOwner===false&&d.setupRequired===false,name:'Service access does not impersonate owner'},
 {path:'/api/auth',body:{action:'setup',password:'fixture-only-123',confirmPassword:'fixture-only-123'},check:(r,d)=>r.status===400&&d.error.includes('proprietário'),name:'Setup requires trusted owner identity'},
 {path:'/api/auth',body:{action:'signup',email:'fixture@example.invalid',password:'fixture-only-123',confirmPassword:'different-fixture'},check:(r,d)=>r.status===400&&d.error.includes('coincidem'),name:'Password mismatch rejected before signup'},
 {path:'/api/rpc',body:{op:'setup_state',p:{}},check:(r,d)=>r.status===400&&d.error.includes('permitida'),name:'Internal setup operation blocked'},
 {path:'/api/rpc',body:{op:'session'},check:(r,d)=>r.status===400,name:'Anonymous session denied'},
 {path:'/api/auth',body:{action:'reset'},origin:'https://invalid.example',check:(r,d)=>r.status===400&&d.error.includes('Origem'),name:'Cross-origin mutation rejected'}
];
for(const t of tests){const r=await fetch(origin+t.path,{method:t.body?'POST':'GET',headers:{...baseHeaders,...(t.body?{'Content-Type':'application/json',Origin:t.origin||origin}:{})},...(t.body?{body:JSON.stringify(t.body)}:{})});let data;try{data=await r.json()}catch{throw Error(t.name+': response was not JSON')}if(!t.check(r,data))throw Error(t.name+': failed ('+r.status+')');console.log('PASS '+t.name)}
