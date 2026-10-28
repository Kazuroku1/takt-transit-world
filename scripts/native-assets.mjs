import sharp from 'sharp';
import { readFile, mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const source = await readFile(new URL('../public/icon.svg', import.meta.url), 'utf8');
const iconDir = new URL('../ios/App/App/Assets.xcassets/AppIcon.appiconset/', import.meta.url);
const splashDir = new URL('../ios/App/App/Assets.xcassets/Splash.imageset/', import.meta.url);
await mkdir(iconDir, { recursive: true });
await mkdir(splashDir, { recursive: true });
const icon = source.replace('rx="30"', 'rx="0"');
await sharp(Buffer.from(icon)).resize(1024,1024).flatten({ background:'#ed7149' }).png().toFile(fileURLToPath(new URL('AppIcon-512@2x.png',iconDir)));
const inner = source.replace(/<svg[^>]*>/,'').replace('</svg>','');
const splash = `<svg xmlns="http://www.w3.org/2000/svg" width="2732" height="2732" viewBox="0 0 2732 2732"><rect width="2732" height="2732" fill="#f5f4ef"/><g transform="translate(1134 1134) scale(3.625)">${inner}</g></svg>`;
const splashFile = new URL('splash-2732x2732.png',splashDir);
await sharp(Buffer.from(splash)).png().toFile(fileURLToPath(splashFile));
await copyFile(splashFile,new URL('splash-2732x2732-1.png',splashDir));
await copyFile(splashFile,new URL('splash-2732x2732-2.png',splashDir));
await sharp(Buffer.from(source)).resize(180,180).flatten({background:'#ed7149'}).png().toFile(fileURLToPath(new URL('../public/apple-touch-icon.png',import.meta.url)));
console.log('Takt app icon, launch screen and Apple touch icon generated.');
