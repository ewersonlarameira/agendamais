export function tenantManifestPath(pathname:string){
 const slug=pathname.split('/').filter(Boolean)[0]||'';
 if(!/^[a-z][a-z0-9-]{2,49}$/.test(slug)||['master','demo','privacidade','termos','api','admin','signin-with-chatgpt','signout-with-chatgpt','callback'].includes(slug))return '/api/manifest';
 return '/api/manifest?tenant='+encodeURIComponent(slug);
}
