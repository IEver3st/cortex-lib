const fs=require('node:fs/promises'),path=require('node:path');
const tools=require('node:fs').existsSync(path.join(__dirname,'node_modules/ag-psd'))?path.join(__dirname,'node_modules'):'C:/Users/User/.codex/tmp/cortex-lib-marketing-tools-20260927/node_modules';
const sharp=require(path.join(tools,'sharp'));
const {createCanvas,loadImage,GlobalFonts}=require(path.join(tools,'@napi-rs/canvas'));
const {writePsdBuffer,readPsd}=require(path.join(tools,'ag-psd'));
const root=path.resolve(__dirname,'..'),W=1920,H=1080;
const ink='#0b111b',blue='#6b9bfa',paper='#f0f0e9',muted='#a9b7cb';
GlobalFonts.registerFromPath('C:/Windows/Fonts/ariblk.ttf','Cortex Heavy');
GlobalFonts.registerFromPath('C:/Windows/Fonts/arial.ttf','Cortex Body');
let layers=[],libraryLogo,gsdLogo;
function layer(name,draw,extra={}){const c=createCanvas(W,H),ctx=c.getContext('2d');draw(ctx);const item={name,imageData:ctx.getImageData(0,0,W,H),...extra};layers.push(item);return c;}
function text(name,content,x,y,size=28,color=paper,font='Cortex Body',options={}){
 return layer(name,ctx=>{ctx.font=`${size}px "${font}"`;ctx.fillStyle=color;ctx.textBaseline='alphabetic';if(options.italic)ctx.transform(1,0,-.17,1,y*.17,0);ctx.fillText(content,x,y);},{text:{text:content,transform:[1,0,options.italic?-.17:0,1,x,y],style:{font:{name:font==='Cortex Heavy'?'Arial-Black':'ArialMT'},fontSize:size,fillColor:{r:parseInt(color.slice(1,3),16),g:parseInt(color.slice(3,5),16),b:parseInt(color.slice(5,7),16)}},shapeType:'point'}});
}
function spaced(name,content,x,y,size,spacing,color){return layer(name,ctx=>{ctx.font=`${size}px "Cortex Body"`;ctx.fillStyle=color;for(const ch of content){ctx.fillText(ch,x,y);x+=ctx.measureText(ch).width+spacing;}});}
function centeredSpaced(name,content,y,size,spacing,color){const c=createCanvas(1,1).getContext('2d');c.font=`${size}px "Cortex Body"`;const w=[...content].reduce((s,ch)=>s+c.measureText(ch).width,0)+(content.length-1)*spacing;return spaced(name,content,(W-w)/2,y,size,spacing,color);}
function rule(name,x,y,w,color=blue,height=3){layer(name,c=>{c.fillStyle=color;c.fillRect(x,y,w,height)});}
async function product(name,x,y,w,{height}={}){const img=await loadImage(path.join(root,'raw',name+'.png'));const h=height||Math.round(img.height*w/img.width);layer('Product capture / '+name,c=>c.drawImage(img,x,y,w,h));}
function wordmark(x,y,size=180){const h=size*.85;layer('Cortex-Lib / supplied library logo',c=>c.drawImage(libraryLogo,x,y-40,h*libraryLogo.width/libraryLogo.height,h));spaced('CORTEX / spaced masthead','CORTEX',x+h*1.15,y-8,size*.14,size*.045,paper);text('LIB / editable product name','LIB',x+h*1.15,y+size*.62,size*.75,blue,'Cortex Heavy',{italic:true});}
async function frame(){
 layer('Background / midnight navy',c=>{c.fillStyle=ink;c.fillRect(0,0,W,H)});
 layer('Corner panels',c=>{c.fillStyle='#08101e';c.beginPath();c.moveTo(0,0);c.lineTo(154,0);c.lineTo(0,154);c.closePath();c.fill();c.beginPath();c.moveTo(1920,785);c.lineTo(1920,1080);c.lineTo(1625,1080);c.closePath();c.fill();});
 layer('Blue diagonal edges',c=>{c.strokeStyle=blue;c.lineWidth=6;c.beginPath();c.moveTo(0,153);c.lineTo(153,0);c.moveTo(1625,1080);c.lineTo(1920,785);c.stroke();c.strokeStyle='#e5ebf6';c.lineWidth=1;c.beginPath();c.moveTo(0,158);c.lineTo(158,0);c.moveTo(1630,1080);c.lineTo(1920,790);c.stroke();});
 spaced('Series name','CORTEX / LIB',112,82,18,4,blue);
 layer('GSD Modifications / original brand asset',c=>c.drawImage(gsdLogo,1678,873,210,210*gsdLogo.height/gsdLogo.width));
}
function detail(titleLines,descriptionLines){wordmark(112,195,110);titleLines.forEach((line,i)=>text('Headline '+(i+1),line,112,440+i*72,56,i?blue:paper,'Cortex Heavy'));descriptionLines.forEach((line,i)=>text('Description '+(i+1),line,112,440+(titleLines.length-1)*72+80+i*38,24,muted));}
async function exportDoc(name,selected=layers){
 const frameNames=new Set(['Corner panels','Blue diagonal edges','GSD Modifications / original brand asset']);
 selected=[...selected.filter(l=>!frameNames.has(l.name)),...selected.filter(l=>frameNames.has(l.name))];
 const c=createCanvas(W,H),ctx=c.getContext('2d');for(const l of selected){const lc=createCanvas(W,H);lc.getContext('2d').putImageData(l.imageData,0,0);ctx.drawImage(lc,0,0);}
 const png=c.toBuffer('image/png');await fs.writeFile(path.join(root,'final',name+'.png'),png);
 const psd={width:W,height:H,imageData:ctx.getImageData(0,0,W,H),children:selected};
 const out=writePsdBuffer(psd,{generateThumbnail:false});await fs.writeFile(path.join(root,'psd',name+'.psd'),out);
 const parsed=readPsd(out,{skipLayerImageData:true,skipCompositeImageData:true,skipThumbnail:true});
 if(parsed.children.length!==selected.length||parsed.width!==W||parsed.height!==H)throw Error('PSD validation failed: '+name);
 return {name,width:W,height:H,layers:parsed.children.length,textLayers:parsed.children.filter(x=>x.text).length,bytes:out.length};
}
async function main(){
 libraryLogo=await loadImage(await sharp(path.join(__dirname,'cortex-lib-logo.png')).trim().png().toBuffer());
 gsdLogo=await loadImage(await sharp(path.join(__dirname,'gsd-logo.png')).trim().png().toBuffer());
 const captures=JSON.parse(await fs.readFile(path.join(__dirname,'captures.json'),'utf8'));
 for(const shot of captures){const dest=path.join(root,'raw',shot.scene+'.png');if(!process.argv.includes('--refresh')&&require('node:fs').existsSync(dest))continue;if(!shot.path)throw Error('Missing capture '+shot.scene);await sharp(shot.path).extract(shot.bounds).png().toFile(dest);}
 const result=[];
 layers=[];await frame();wordmark(112,285,250);text('Hero headline','UI for your',112,603,48,paper,'Cortex Heavy');text('Hero headline 2','FiveM resources.',112,666,48,blue,'Cortex Heavy');text('Hero description','Add menus, notifications, dialogs and settings',112,740,24,muted);text('Hero description 2','through one shared library.',112,778,24,muted);await product('menus',830,235,475);await product('radial',1370,245,380);await product('interactions',1370,676,310);result.push(await exportDoc('01-cortex-lib'));
 layers=[];await frame();detail(['NOTIFICATIONS'],['Show confirmations, warnings and errors.','Choose their position and display duration.']);await product('notifications',875,235,800);result.push(await exportDoc('02-notifications'));
 layers=[];await frame();detail(['LIST & RADIAL','MENUS'],['Add actions, toggles and selectable values.','Navigate with the keyboard or mouse.']);await product('menus',835,235,490);await product('radial',1360,335,425);result.push(await exportDoc('03-menus-and-radial'));
 layers=[];await frame();detail(['INPUT DIALOGS'],['Collect text, selections and checkbox values.','Set required fields and button labels.']);await product('dialogs',885,245,770);result.push(await exportDoc('04-input-dialogs'));
 layers=[];await frame();wordmark(1530,170,100);text('Settings headline','RESOURCE SETTINGS',112,205,56,paper,'Cortex Heavy');text('Settings description','Group settings by resource, search by name, and preview changes before saving.',112,255,24,muted);await product('settings',245,310,1200);result.push(await exportDoc('05-shared-settings'));
 layers=[];await frame();detail(['INTERACTION','PROMPTS'],['Show the action and its assigned key.','Use screen prompts or world anchors.']);await product('interactions',960,370,650);result.push(await exportDoc('06-interaction-prompts'));
 // Reusable transparent overlays, with each corner and original brand mark on separate layers.
 layers=[];await frame(0,'');const overlayLayers=layers.filter(l=>['Corner panels','Blue diagonal edges','GSD Modifications / original brand asset'].includes(l.name));
 const blank=createCanvas(W,H),bc=blank.getContext('2d');for(const l of overlayLayers){const lc=createCanvas(W,H);lc.getContext('2d').putImageData(l.imageData,0,0);bc.drawImage(lc,0,0);}await fs.writeFile(path.join(root,'overlays','cortex-lib-frame.png'),blank.toBuffer('image/png'));await fs.writeFile(path.join(root,'psd','cortex-lib-frame.psd'),writePsdBuffer({width:W,height:H,imageData:bc.getImageData(0,0,W,H),children:overlayLayers}));
 layers=[...overlayLayers];layer('Cortex-Lib / supplied library logo',c=>c.drawImage(libraryLogo,510,355,300,282));text('LIB / editable product name','LIB',852,625,300,blue,'Cortex Heavy',{italic:true});centeredSpaced('CORTEX / spaced masthead','CORTEX',300,29,17,paper);rule('Masthead left rule',620,287,175);rule('Masthead right rule',1125,287,175);centeredSpaced('Overlay descriptor','UI & UTILITY LIBRARY',722,29,7,paper);rule('Overlay title underline',590,755,740);centeredSpaced('Overlay features','MENUS  /  NOTIFICATIONS  /  SETTINGS',812,20,3,blue);
 const tc=createCanvas(W,H),tctx=tc.getContext('2d');for(const l of layers){const lc=createCanvas(W,H);lc.getContext('2d').putImageData(l.imageData,0,0);tctx.drawImage(lc,0,0);}await fs.writeFile(path.join(root,'overlays','cortex-lib-title.png'),tc.toBuffer('image/png'));await fs.writeFile(path.join(root,'psd','cortex-lib-title.psd'),writePsdBuffer({width:W,height:H,imageData:tctx.getImageData(0,0,W,H),children:layers}));
 await fs.writeFile(path.join(root,'source','export-validation.json'),JSON.stringify(result,null,2));
 const sheet=createCanvas(1440,1215),sc=sheet.getContext('2d');sc.fillStyle=ink;sc.fillRect(0,0,1440,1215);for(let i=0;i<result.length;i++){const im=await loadImage(path.join(root,'final',result[i].name+'.png'));sc.drawImage(im,(i%2)*720,Math.floor(i/2)*405,720,405);}await fs.writeFile(path.join(root,'contact-sheet.png'),sheet.toBuffer('image/png'));
 console.log(JSON.stringify(result,null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1});
